# Agent Memory: Introduction to context and memory engineering

Build a memory-aware incident-handover assistant for enterprise platform teams.
Alice handles a checkout incident; Bob handles a separate payroll incident.
One workshop database account stores the synthetic incidents and shared runbooks.
User/thread scopes select relevant evidence; they are **not access controls**.

Open [notebook_student_ollama.ipynb](notebook_student_ollama.ipynb) for the
exercises or [notebook_complete_ollama.ipynb](notebook_complete_ollama.ipynb)
for the worked solution. They have matching cell IDs, 16 exercise prompts and
checkpoints. Code cells are capped at 24 lines. Allow 120–150 minutes;
local model speed affects extraction and generation time.

Both notebooks include a reference architecture, educational explanations and
section-level key-takeaway callouts. The diagram is embedded for offline
rendering; [reference_architecture.svg](reference_architecture.svg) is its
editable source. Supporting Python is included in short provided cells.
No separate helper module, test suite or validation script is required.

## Alignment with the hosted session

| Session outcome | Runnable lab evidence |
|---|---|
| Episodic memory | Incident messages, offloaded diagnostics and a persistent thread summary |
| Semantic memory | Typed facts/preferences, reviewed supersession and graph retrieval |
| Procedural memory | Shared runbooks and a reviewed, versioned personal checklist |
| LangChain and Python agents | `create_agent` with `ChatOllama`, scoped read-only tools and a bounded loop |
| Persistent state and cross-session recall | Oracle-backed messages and workflow metadata; reopen the client and rebuild the agent |
| Offloading and compaction | Persist full diagnostics, pass a small reference and inspect a bounded summary |
| Retrieval and indexing | Inspect managed indexes; explain chunking, dimensions, candidate limits and exact/ANN evaluation |
| Ingestion → recall → reasoning → action | Ingest the request, recall through tools, draft with Ollama and separately approve a database write |
| Reusable patterns that improve over time | Promote a reviewed incident lesson and recall it in a new agent session |
| Production-oriented patterns | Narrow tools, human review, provenance, quality measurement, retention and scoped cleanup |

The teaching agent persists conversation/application state in Oracle, not a
second in-memory vector store. It does not claim exactly-once tool execution
or crash-resumable LangGraph checkpoints. The local approval gate illustrates
host-controlled writes; production requires authenticated approvers, durable
authorization/idempotency and independently retained audit records.

> **Workshop boundary**
>
> There is no IAM group, end-user token setup or Deep Data Security exercise.
> Both client objects connect as the same database user and can access all
> records in the workshop schema. The scope comparison demonstrates this.
> Use synthetic data and a dedicated schema per participant. A real multi-user
> service needs a separately designed authorization layer.

Suggested facilitation: 15 minutes setup/architecture, 25 minutes memory and
extraction, 25 minutes evolution/retrieval, 35 minutes context engineering and
the agent loop, and 20 minutes scope/retention/review. Prepare models and
database accounts before the session.

## OAMP 26.8 capabilities explored

| Capability | Exercise |
|---|---|
| Background extraction | Ingest messages, drain background work and inspect persisted output |
| Post-extraction linking | An additional LLM call proposes relationships; review their correctness |
| Memory evolution and graph search | Explicit supersession, invalid history and bounded graph expansion |
| Search post-processing | Database reranking, token budgets and comparison with Ollama pruning |
| Record listing | Inspect memories and threads through public APIs |
| Observability | Collect operation counts without copying prompts or content |
| Context and retention | Typed records, metadata filters, context cards, TTL and cross-session continuity |
| Retrieval quality | Compare known-answer results without assuming reranking always improves recall |

The lab is text-only and needs no vision model. It never executes production
remediation or treats recalled text as authority to change infrastructure.

## Prerequisites

The original image installs OAMP 26.4 and python-oracledb 3.4.2.
Use this lab's isolated kernel instead of upgrading the shared environment
used by older notebooks.

You need:

1. Oracle AI Database supporting **`DBMS_VECTOR_CHAIN.UTL_TO_RERANK` with
   `provider="database"`**. An installed model or a “26ai” product label alone
   does not prove compatible inference. The notebook checks actual calls and
   has no remote-reranker or simulated-output fallback.
2. One dedicated workshop schema (default `ZH_LAB`) with privileges to create
   OAMP's objects and use the two database models.
3. An imported 384-dimensional embedding model, default
   `PRISM.ALL_MINILM_L12_V2`, with a 256-token input limit.
4. An Oracle-compatible ONNX reranker, default `ZH_LAB.ZH_RERANKER`.
   Use the OML4Py preconfigured `BAAI/bge-reranker-base` pipeline with its
   required preprocessing. A plain Hugging Face ONNX file is not interchangeable.
5. Ollama with `llama3.2` pulled. The notebook checks structured JSON and
   requires actual LangChain tool calls. Select a stronger tool-capable local
   model with `OLLAMA_MODEL` if needed. No paid model API keys are used.

### Optional instructor provisioning

Skip this script if an instructor already provided a suitable schema and
models. It is opt-in and does not change existing workshops by default.

In an OML4Py-supported export environment, follow Oracle's [ONNX conversion
instructions][onnx]:

```python
from oml.utils import ONNXPipeline

pipeline = ONNXPipeline(model_name="BAAI/bge-reranker-base")
pipeline.export2file("zh_reranker", output_dir=".")
```

Stage `zh_reranker.onnx` on the database server under `/opt/oracle/dmdump`,
which the original image exposes through the `DM_DUMP` directory object.
Do not commit model binaries or credentials. Run
[`60-agent-memory-zero-to-hero.sh`](../../db-startup/60-agent-memory-zero-to-hero.sh)
inside the disposable workshop database container with these environment values:

```text
ENABLE_AGENT_MEMORY_ZERO_TO_HERO=1
ZH_DB_PASSWORD=<new workshop password>
ZH_EMBED_MODEL=PRISM.ALL_MINILM_L12_V2
ZH_RERANK_FILE=zh_reranker.onnx
```

The script creates only `ZH_LAB`, grants object/model privileges and imports
the reranker. It creates no IAM mappings, security policies or additional
runtime/admin accounts. It fails if `ZH_LAB` already exists; it never overwrites
an existing account. DDL commits independently: inspect partial setup before
retrying. For another deployment, ask its administrator to prepare an
equivalent dedicated schema rather than running container-specific SYSDBA setup.
Do not reuse an older, policy-protected version of this lab's store.

### Install and select the separate kernel

From this folder in the Jupyter environment:

```bash
bash setup_kernel.sh
```

Select **Agent Memory 26.8 (Ollama)** and restart the kernel. Python 3.13 is
recommended; the interpreter needs a compatible published OAMP wheel.
Direct dependencies are pinned in `requirements.txt`; `pip check` must pass.

### Configuration

Set these in the notebook server's environment before launching the kernel.
The password is requested through a hidden prompt if absent. Never place
credentials in source, saved output or a committed environment file.

| Variable | Default / purpose |
|---|---|
| `ZH_DB_USER`, `ZH_DB_PASSWORD` | `ZH_LAB`; the only workshop account |
| `ZH_DB_DSN` | `aidbfree:1521/FREEPDB1`; use your database's published host/port when running outside the container network |
| `ZH_EMBED_MODEL` | `PRISM.ALL_MINILM_L12_V2` |
| `ZH_RERANK_MODEL` | `ZH_LAB.ZH_RERANKER` |
| `OLLAMA_BASE_URL` | `http://ollama:11434`; use `http://localhost:11434` for host-published Ollama |
| `OLLAMA_MODEL` | `llama3.2` |

For a local Docker database publishing port 1522, for example, use
`localhost:1522/FREEPDB1`. Confirm the container's actual port and model names;
grant the workshop account access to any models owned by another schema.
An existing reranker is usable only after the notebook's `UTL_TO_RERANK`
preflight succeeds; a successful direct `PREDICTION` call is not equivalent.

The store is `ZH_INCIDENTS`. Every fresh kernel gets a unique run ID and
application labels. Rerun from a fresh kernel instead of repeating write cells.
Cleanup deletes only this run's two threads and their dependent records.
Shared runbooks retain their 30-day TTL; TTL is not physical erasure.
The instructor manages eventual store/schema cleanup separately.

## Before hosting the session

Execute the complete notebook from a fresh kernel on the intended stack.
Retain the in-notebook checkpoints: they help students interpret actual output.
Confirm model preflight, persisted extraction, supersession/graph behavior,
the retrieval score table, scope comparison, compaction, actual agent tool
calls, cross-session recovery, the approval gate, procedural recall and
post-cleanup row/chunk counts. Record database RU, model versions and commit.
An unavailable database/model is a missing prerequisite, not a passing result.

This simplified edition removes the identity-provider requirement. Full
end-to-end acceptance remains pending a compatible in-database reranker on
the local stack; do not describe structural validation as a completed lab run.

## Sources

- [OAMP 26.8 release notes][release]
- [OAMP memory API][memory]
- [OAMP model and reranker interfaces][models]
- [Database ONNX reranking parameters][rerank]
- [LangChain agent factory](https://reference.langchain.com/python/langchain/agents/factory/create_agent)
- [LangChain ChatOllama](https://reference.langchain.com/python/langchain-ollama/chat_models/ChatOllama)

[release]: https://docs.oracle.com/en/database/oracle/agent-memory/26.8/guide/whats-new.html
[memory]: https://docs.oracle.com/en/database/oracle/agent-memory/26.8/guide/api/agentmemory.html
[models]: https://docs.oracle.com/en/database/oracle/agent-memory/26.8/guide/api/models.html
[rerank]: https://docs.oracle.com/en/database/oracle/oracle-database/26/arpls/dbms_vector_chain1.html
[onnx]: https://docs.oracle.com/en/database/oracle/machine-learning/oml4py/2-23ai/mlpug/convert-pretrained-models-onnx-model-end-end-instructions.html
