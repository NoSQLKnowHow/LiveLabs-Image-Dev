"""Small I/O adapters; the teaching notebook keeps OAMP operations visible.

There are no mock providers or owner-connection fallbacks in this module.
"""
from __future__ import annotations

import asyncio
import getpass
import hashlib
import json
import math
import os
import re
from contextlib import contextmanager

import oracledb
from oracleagentmemory.apis import IReranker, RerankResponse, RerankResponseResult
from oracleagentmemory.core.deepsec import (
    OracleMemoryEndUserSecurityContext, get_end_user_username,
)


def identifier(value: str) -> str:
    """Only unquoted Oracle identifiers, optionally schema-qualified."""
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{0,127}(\.[A-Za-z][A-Za-z0-9_]{0,127})?", value):
        raise ValueError("Expected an unquoted Oracle identifier")
    return value.upper()


def secret(name: str) -> str:
    value = os.getenv(name) or getpass.getpass(f"{name}: ")
    if not value.strip():
        raise ValueError(f"{name} is required; see README.md")
    return value


def make_pool(user: str, password_variable: str, dsn: str):
    return oracledb.create_pool(
        user=user, password=secret(password_variable), dsn=dsn,
        min=1, max=4, increment=1,
    )


@contextmanager
def protected_connection(pool, security_context):
    """Raw SQL does not inherit OAMP's context manager; attach it explicitly."""
    if security_context is None:
        raise ValueError("An authenticated end-user context is required")
    connection = pool.acquire()
    try:
        connection.set_end_user_security_context(security_context)
        if get_end_user_username(connection) is None:
            raise RuntimeError("Database did not authenticate the end user")
        yield connection
    finally:
        try:
            connection.clear_end_user_security_context()
        except Exception:
            # Never return a session with unknown identity state to the pool.
            pool.drop(connection)
            raise
        else:
            pool.release(connection)


def authenticated_username(pool, security_context) -> str:
    with protected_connection(pool, security_context) as connection:
        return get_end_user_username(connection)


def normalize_ranking(payload, documents: list[str]) -> RerankResponse:
    """Adapt Oracle's JSON response to the complete OAMP reranker contract.

    Accept either index convention only when the full permutation proves it.
    Partial results, duplicate indexes and non-finite scores are failures.
    """
    if hasattr(payload, "read"):
        payload = payload.read()
    if isinstance(payload, (str, bytes)):
        payload = json.loads(payload)
    rows = payload.get("results") if isinstance(payload, dict) else payload
    if not isinstance(rows, list) or len(rows) != len(documents):
        raise ValueError("Database reranker must return every candidate")
    indexes = []
    for row in rows:
        raw = row["index"]
        if isinstance(raw, bool) or not re.fullmatch(r"\d+", str(raw)):
            raise ValueError("Reranker indexes must be integers")
        indexes.append(int(raw))
    if sorted(indexes) == list(range(len(documents))):
        offset = 0
    elif sorted(indexes) == list(range(1, len(documents) + 1)):
        offset = 1
    else:
        raise ValueError("Reranker indexes must be a complete permutation")
    results = []
    for row, index in zip(rows, indexes):
        score = float(row["score"])
        if not math.isfinite(score):
            raise ValueError("Reranker scores must be finite")
        index -= offset
        results.append(RerankResponseResult(index, score, documents[index]))
    return RerankResponse(sorted(results, key=lambda row: (-row.relevance_score, row.index)))


class OracleDatabaseReranker(IReranker):
    """ONNX inference in Oracle, not a REST call made by the database.

    Requires a database RU supporting UTL_TO_RERANK provider=database and
    an Oracle-compatible ONNX reranker imported by the instructor.
    """
    def __init__(self, pool, model: str, security_context):
        if security_context is None:
            raise ValueError("Reranking must run as the authenticated end user")
        self.pool = pool
        self.model = identifier(model)
        self.security_context = security_context

    def rerank(self, query: str, documents: list[str], **kwargs) -> RerankResponse:
        if not documents:
            return RerankResponse([])
        params = {"provider": "database", "model": self.model,
                  "return_docs": True, "top_n": len(documents)}
        with protected_connection(self.pool, self.security_context) as connection:
            with connection.cursor() as cursor:
                cursor.setinputsizes(query=oracledb.DB_TYPE_CLOB,
                                     documents=oracledb.DB_TYPE_CLOB,
                                     params=oracledb.DB_TYPE_CLOB)
                cursor.execute(
                    "SELECT JSON_SERIALIZE(DBMS_VECTOR_CHAIN.UTL_TO_RERANK("
                    ":query, JSON(:documents), JSON(:params)) RETURNING CLOB) FROM dual",
                    query=query, documents=json.dumps({"documents": documents}),
                    params=json.dumps(params),
                )
                payload = cursor.fetchone()[0]
                if hasattr(payload, "read"):
                    payload = payload.read()
        return normalize_ranking(payload, documents)

    async def rerank_async(self, query: str, documents: list[str], **kwargs):
        # Each worker acquires its own session and attaches the same verified context.
        return await asyncio.to_thread(self.rerank, query, documents, **kwargs)


def expect_denied(operation, *, object_existence_verified=False):
    """A syntax error, missing model or network failure is NOT an isolation pass."""
    try:
        operation()
    except Exception as exc:
        codes = "01031|41900|28115"
        # A standard session can hide a real, inaccessible table as ORA-00942.
        # Accept that ONLY after the caller proved the same object exists.
        if object_existence_verified:
            codes += "|00942"
        if not re.search(rf"ORA-({codes})\b", str(exc)):
            raise
        return "Database denied the operation"
    raise AssertionError("Expected database authorization to reject this operation")


def show_hits(hits):
    for hit in hits:
        print(f"{hit.id} [{hit.record.record_type}] {hit.content}")


def hit_at_k(hits, expected_id: str, k: int = 3) -> int:
    """One relevant record per fixture query: Hit@k equals Recall@k here."""
    return int(expected_id in [hit.id for hit in hits[:k]])


def approval_phrase(draft: str, run_id: str) -> str:
    if not isinstance(draft, str) or not 1 <= len(draft.strip()) <= 8000:
        raise ValueError("A handover must contain 1–8,000 characters")
    digest = hashlib.sha256(json.dumps([run_id, draft]).encode()).hexdigest()
    return f"APPROVE {digest}"


def save_approved_handover(thread, security_context, draft, approval, run_id):
    """Host-only lab action: no model-supplied identity, target or approval.

    This is deliberately NOT registered as an agent tool. A real service must
    authenticate the approver and persist an independent authorization record.
    """
    expected = approval_phrase(draft, run_id)
    if approval != expected:
        raise PermissionError("The reviewed draft requires explicit host approval")
    if security_context is None:
        raise ValueError("An authenticated end-user context is required")
    with OracleMemoryEndUserSecurityContext(security_context):
        return thread.add_memory(
            draft, memory_type="memory", autonomous_linking=False,
            memory_id=f"handover-{run_id}",
            metadata={"run": run_id, "source": "approved-handover",
                      "approval_digest": expected.split()[1]},
        )
