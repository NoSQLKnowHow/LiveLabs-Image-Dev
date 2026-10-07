"""Unit contracts only: no database, IAM or Ollama security claims."""
import asyncio
import json
import sys
import unittest
from contextlib import nullcontext
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import lab_support as lab


class RankingTests(unittest.TestCase):
    def test_zero_based_and_descending(self):
        result = lab.normalize_ranking(
            [{"index": 0, "score": 0.1}, {"index": 1, "score": 0.9}], ["a", "b"])
        self.assertEqual([row.index for row in result.results], [1, 0])
        self.assertEqual(result.results[0].document, "b")

    def test_one_based_json_envelope(self):
        payload = json.dumps({"results": [{"index": "1", "score": "0.3"},
                                         {"index": "2", "score": "0.8"}]})
        self.assertEqual(lab.normalize_ranking(payload, ["a", "b"]).results[0].index, 1)

    def test_ties_preserve_input_order(self):
        result = lab.normalize_ranking(
            [{"index": 1, "score": 0}, {"index": 0, "score": 0}], ["a", "b"])
        self.assertEqual([row.index for row in result.results], [0, 1])

    def test_invalid_responses_fail_closed(self):
        bad_rows = [
            [], [{"index": 0, "score": 1}],
            [{"index": 0, "score": 1}, {"index": 0, "score": 1}],
            [{"index": -1, "score": 1}, {"index": 1, "score": 1}],
            [{"index": 0.5, "score": 1}, {"index": 1, "score": 1}],
            [{"index": True, "score": 1}, {"index": 0, "score": 1}],
            [{"index": 0, "score": float("nan")}, {"index": 1, "score": 1}],
            [{"index": 0, "score": float("inf")}, {"index": 1, "score": 1}],
        ]
        for rows in bad_rows:
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                lab.normalize_ranking(rows, ["a", "b"])

    def test_identifier_validation(self):
        self.assertEqual(lab.identifier("owner.model_1"), "OWNER.MODEL_1")
        for name in ['owner.model;drop table x', 'a b', '"a"', 'a.b.c', '']:
            with self.subTest(name=name), self.assertRaises(ValueError):
                lab.identifier(name)


class ContextTests(unittest.TestCase):
    def setUp(self):
        self.pool, self.connection, self.context = MagicMock(), MagicMock(), object()
        self.pool.acquire.return_value = self.connection
        self.username = patch.object(lab, "get_end_user_username", return_value="alice")
        self.username.start()
        self.addCleanup(self.username.stop)

    def test_context_is_attached_and_cleared(self):
        with lab.protected_connection(self.pool, self.context) as connection:
            self.assertIs(connection, self.connection)
            self.connection.set_end_user_security_context.assert_called_once_with(self.context)
        self.connection.clear_end_user_security_context.assert_called_once()
        self.pool.release.assert_called_once_with(self.connection)

    def test_clear_failure_discards_session_instead_of_reusing_it(self):
        self.connection.clear_end_user_security_context.side_effect = RuntimeError("clear failed")
        with self.assertRaisesRegex(RuntimeError, "clear failed"):
            with lab.protected_connection(self.pool, self.context):
                pass
        self.pool.drop.assert_called_once_with(self.connection)
        self.pool.release.assert_not_called()

    def test_cleanup_on_query_failure(self):
        with self.assertRaisesRegex(RuntimeError, "query failed"):
            with lab.protected_connection(self.pool, self.context):
                raise RuntimeError("query failed")
        self.connection.clear_end_user_security_context.assert_called_once()

    def test_cleanup_when_attachment_fails(self):
        self.connection.set_end_user_security_context.side_effect = RuntimeError("bad token")
        with self.assertRaisesRegex(RuntimeError, "bad token"):
            with lab.protected_connection(self.pool, self.context):
                self.fail("Unauthenticated work must never run")
        self.connection.clear_end_user_security_context.assert_called_once()

    def test_reject_null_context_before_acquiring(self):
        with self.assertRaises(ValueError):
            with lab.protected_connection(self.pool, None):
                pass
        self.pool.acquire.assert_not_called()

    def test_reject_missing_authenticated_user(self):
        with patch.object(lab, "get_end_user_username", return_value=None):
            with self.assertRaises(RuntimeError):
                with lab.protected_connection(self.pool, self.context):
                    pass
        self.connection.clear_end_user_security_context.assert_called_once()

    def test_reranker_binds_values_and_uses_database_provider(self):
        cursor = self.connection.cursor.return_value.__enter__.return_value
        cursor.fetchone.return_value = ('[{"index":0,"score":0.8},{"index":1,"score":0.1}]',)
        reranker = lab.OracleDatabaseReranker(self.pool, "owner.reranker", self.context)
        query = "pool'; DROP TABLE nope; --"
        result = reranker.rerank(query, ["first", "second"])
        sql = cursor.execute.call_args.args[0]
        binds = cursor.execute.call_args.kwargs
        self.assertNotIn(query, sql)
        self.assertIn("UTL_TO_RERANK", sql)
        self.assertEqual(binds["query"], query)
        self.assertEqual(json.loads(binds["documents"]), {"documents": ["first", "second"]})
        self.assertEqual(json.loads(binds["params"]), {
            "provider": "database", "model": "OWNER.RERANKER", "return_docs": True, "top_n": 2})
        self.assertEqual(len(result.results), 2)
        self.connection.clear_end_user_security_context.assert_called_once()

    def test_empty_candidates_do_not_borrow_a_session(self):
        result = lab.OracleDatabaseReranker(self.pool, "model", self.context).rerank("q", [])
        self.assertEqual(result.results, [])
        self.pool.acquire.assert_not_called()

    def test_async_path_attaches_context_in_worker(self):
        cursor = self.connection.cursor.return_value.__enter__.return_value
        cursor.fetchone.return_value = ('[{"index":0,"score":0.8}]',)
        reranker = lab.OracleDatabaseReranker(self.pool, "model", self.context)
        result = asyncio.run(reranker.rerank_async("q", ["text"]))
        self.assertEqual(result.results[0].index, 0)
        self.connection.set_end_user_security_context.assert_called_once_with(self.context)
        self.connection.clear_end_user_security_context.assert_called_once()


class DenialTests(unittest.TestCase):
    def test_hidden_table_requires_positive_existence_control(self):
        operation = MagicMock(side_effect=RuntimeError("ORA-00942: table hidden"))
        with self.assertRaises(RuntimeError):
            lab.expect_denied(operation)
        self.assertIn("denied", lab.expect_denied(operation, object_existence_verified=True))

    def test_expected_authorization_errors(self):
        for code in ("01031", "41900", "28115"):
            with self.subTest(code=code):
                operation = MagicMock(side_effect=RuntimeError(f"ORA-{code}: denied"))
                self.assertIn("denied", lab.expect_denied(operation))

    def test_other_errors_are_not_security_passes(self):
        for message in ("ORA-00942: table missing", "ORA-00904: bad column",
                        "ORA-12541: no listener", "model missing"):
            with self.subTest(message=message), self.assertRaises(RuntimeError):
                lab.expect_denied(MagicMock(side_effect=RuntimeError(message)))

    def test_successful_forbidden_operation_is_failure(self):
        with self.assertRaises(AssertionError):
            lab.expect_denied(lambda: None)


class ApprovalTests(unittest.TestCase):
    def test_digest_binds_text_and_run(self):
        self.assertNotEqual(lab.approval_phrase("draft", "run1"),
                            lab.approval_phrase("draft", "run2"))
        self.assertNotEqual(lab.approval_phrase("draft", "run1"),
                            lab.approval_phrase("changed", "run1"))

    def test_unapproved_write_never_calls_database(self):
        thread = MagicMock()
        with self.assertRaises(PermissionError):
            lab.save_approved_handover(thread, object(), "draft", "", "run1")
        thread.add_memory.assert_not_called()

    def test_changed_content_invalidates_approval(self):
        thread = MagicMock()
        with self.assertRaises(PermissionError):
            lab.save_approved_handover(thread, object(), "modified",
                                      lab.approval_phrase("draft", "run1"), "run1")
        thread.add_memory.assert_not_called()

    def test_approved_write_is_thread_scoped(self):
        thread, context = MagicMock(), object()
        thread.add_memory.return_value = "receipt"
        with patch.object(lab, "OracleMemoryEndUserSecurityContext", return_value=nullcontext()) as ctx:
            receipt = lab.save_approved_handover(
                thread, context, "draft", lab.approval_phrase("draft", "run1"), "run1")
        self.assertEqual(receipt, "receipt")
        ctx.assert_called_once_with(context)
        kwargs = thread.add_memory.call_args.kwargs
        self.assertNotIn("user_id", kwargs)
        self.assertNotIn("thread_id", kwargs)
        self.assertEqual(kwargs["memory_id"], "handover-run1")
        self.assertEqual(kwargs["metadata"]["source"], "approved-handover")

    def test_reject_unbounded_or_empty_drafts(self):
        for draft in ("", "  ", "x" * 8001):
            with self.subTest(length=len(draft)), self.assertRaises(ValueError):
                lab.approval_phrase(draft, "run")


if __name__ == "__main__":
    unittest.main()
