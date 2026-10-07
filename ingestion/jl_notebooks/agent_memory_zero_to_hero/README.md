# Agent Memory: zero to hero with Ollama

Build a memory-aware incident-handover assistant for enterprise platform teams.
Alice handles a checkout incident; Bob handles a separate payroll incident.
Both can read approved runbooks, but database authorization protects their
private notes even when a caller supplies someone else's `user_id`.

Open [notebook_student_ollama.ipynb](notebook_student_ollama.ipynb) for the
exercises or [notebook_complete_ollama.ipynb](notebook_complete_ollama.ipynb)
for the worked solution. They have matching cell IDs, exercise prompts and
checkpoints. Teaching cells are capped at 24 lines. Allow 120–150 minutes;
local model speed affects extraction and generation time.

## Alignment with the hosted session

| Session outcome | Runnable lab evidence |
|---|---|
| Episodic memory | Incident messages, diagnostic episodes and a persistent thread summary |
| Semantic memory | Typed facts/preferences, reviewed supersession and graph retrieval |
| Procedural memory | Shared approved runbooks plus a reviewed, versioned personal checklist |
| LangChain and Python agents | `create_agent` with `ChatOllama`, scoped recall/diagnostic tools and a bounded loop |
| Persistent state and cross-session recall | Oracle-backed messages and workflow metadata; close/reopen the client and rebuild the agent |
| Offloading and compaction | Persist full diagnostics, pass a small reference, retrieve on demand and inspect a bounded summary |
| Retrieval and indexing | Inspect managed indexes; explain chunking, embedding dimensions, candidate limits and exact/ANN evaluation |
| Ingestion → recall → reasoning → action | Ingest the request, recall through tools, draft with Ollama and separately approve a scoped database write |
| Reusable patterns that improve over time | Promote a reviewed incident lesson to procedural memory and recall it from a new agent session |
| Production-oriented boundaries | End-user authorization, no owner fallback, separate approval, retention, negative tests and regression evidence |

The teaching agent persists conversation/application state in Oracle, not a
second in-memory vector store. It does not claim exactly-once tool execution
or crash-resumable LangGraph checkpoints. The write gate is a local classroom
approval demonstration; production needs authenticated approvers, durable
authorization/idempotency and independently retained audit records.

Suggested facilitation: 15 minutes setup/architecture, 25 minutes secure memory
and extraction, 25 minutes evolution/retrieval, 35 minutes context engineering
and the agent loop, and 20 minutes security/retention/review. Allow extra time
for small local models. Provision IAM and database models before the session.

## What this adds to the original workshop

| Capability | Exercise |
|---|---|
| OAMP 26.8 Deep Data Security | Own-row and global-read policies; authenticated contexts; adversarial read/write checks |
| Background extraction | Ollama extracts typed memories; explicitly drain work and inspect persisted output |
| Automatic memory links | `POST_EXTRACTION` uses an additional LLM call to propose relationships |
| Memory evolution and graph search | Explicit supersession, invalid history, bounded graph expansion |
| Configurable search post-processing | Database reranking, token budgets, optional comparison with Ollama pruning |
| Record listing | Inspect memories and threads through public APIs |
| Observability | Collect operation counts without prompts, content or tokens |
| Established memory features | Typed records, metadata filters, TTL, context cards, cross-session continuity |
| Regression evidence | Known-answer retrieval fixture; compare results without assuming reranking always improves recall |

The lab is text-only. It does not require the new image features or a vision
model. It never executes production remediation or treats recalled text as
authorization to change infrastructure.

## Instructor prerequisites

The original image installs OAMP 26.4 and python-oracledb 3.4.2. Neither is
sufficient for this lab. Use the isolated kernel below; do not upgrade the
shared environment used by the older notebooks.

The full lab also needs:

1. An Oracle AI Database deployment with **Deep Data Security** and
   **`DBMS_VECTOR_CHAIN.UTL_TO_RERANK` with `provider="database"`** enabled.
   A product name of “26ai” alone does not prove that its installed RU has both.
   The current workshop image may need a database update or a separately
   provisioned database. The notebook stops on missing capabilities; there is
   no simulated security or remote-reranker fallback.
2. The repository's `PRISM.ALL_MINILM_L12_V2` embedding model (384 dimensions).
   Its `max_input_tokens=256` is explicit; the lab's fixture records are short.
3. An Oracle-compatible ONNX **reranking** model imported as
   `ZH_OWNER.ZH_RERANKER`. Use the OML4Py preconfigured
   `BAAI/bge-reranker-base` pipeline, which includes the required preprocessing.
   A plain Hugging Face ONNX file is not an interchangeable import.
4. Ollama with `llama3.2` pulled, as in the existing image. The notebook checks
   the model endpoint and structured JSON output before starting extraction,
   and requires actual LangChain tool calls during the agent exercises.
   A stronger tool-capable local model can be selected through `OLLAMA_MODEL`.
   The agent has no remote tracing or production remediation tools.
5. An isolated OCI IAM/Deep Data Security configuration with a database resource,
   application identity, database-access token, and **two different end-user
   access tokens**. Both users must belong to the dedicated `ZH_IAM_GROUP`,
   with group claims configured in the tokens. These are database/IAM tokens,
   not OpenAI or Anthropic API keys. Use the [official OAMP deployment guide][security].
   The lab does not fabricate tokens, enable trust by user-name strings, or
   modify database-wide identity-provider settings.
6. Separate owner, security-administrator and application-pool credentials.
   The notebook uses the first two only for initial store setup and policy
   assignment, then closes those sessions before student runtime operations.
   In a hosted class, an instructor should perform the setup section.

### Prepare the models and accounts

In an OML4Py-supported export environment, follow Oracle's [ONNX conversion
instructions][onnx] and export the preconfigured reranker:

```python
from oml.utils import ONNXPipeline

pipeline = ONNXPipeline(model_name="BAAI/bge-reranker-base")
pipeline.export2file("zh_reranker", output_dir=".")
```

Stage the resulting `zh_reranker.onnx` on the database server under
`/opt/oracle/dmdump`, alongside the existing embedding artifact. Do not commit
model binaries or credentials. Run the opt-in
[`60-agent-memory-zero-to-hero.sh`](../../db-startup/60-agent-memory-zero-to-hero.sh)
inside the disposable workshop database container with these environment values:

```text
ENABLE_AGENT_MEMORY_ZERO_TO_HERO=1
ZH_OWNER_PASSWORD=<new owner password>
ZH_APP_PASSWORD=<different runtime password>
ZH_IAM_GROUP=<dedicated configured IAM group>
ZH_RERANK_FILE=zh_reranker.onnx
```

The script creates `ZH_OWNER`, `ZH_APP`, the reranker and a model-access role
mapped to the IAM group. It does not grant the pool account table or model
access: model privileges are carried by the end-user data role. It fails if
the accounts or group mapping already exist. Oracle DDL commits independently;
after a partial setup failure, inspect the created objects before retrying.
An instructor using Autonomous Database should apply the same account/role
separation through its administrator instead of the container's SYSDBA entry.

### Install and select the separate kernel

From this folder, in the Jupyter environment:

```bash
bash setup_kernel.sh
```

Select **Agent Memory 26.8 (Ollama)** and restart the kernel. Python 3.13 is
recommended; the chosen interpreter must have a compatible published OAMP wheel.
Direct dependencies are pinned in `requirements.txt`; `pip check` must pass.

### Configuration

Set values in the notebook server's environment before launching the kernel.
Missing passwords/tokens are requested with `getpass`; never paste them into a
code cell, saved output, or a committed `.env` file.

| Variable | Default / purpose |
|---|---|
| `ZH_DB_DSN` | `aidbfree:1521/FREEPDB1`; use your approved TCPS/wallet configuration outside the local container network |
| `ZH_OWNER`, `ZH_OWNER_PASSWORD` | `ZH_OWNER`; setup only |
| `ZH_ADMIN`, `ZH_ADMIN_PASSWORD` | `ADMIN`; security-policy administration only |
| `ZH_APP`, `ZH_APP_PASSWORD` | `ZH_APP`; no fallback table privileges |
| `ZH_IAM_GROUP` | Required; same group as the provisioning script |
| `ZH_DATABASE_ACCESS_TOKEN` | Application's database-access token |
| `ZH_ALICE_TOKEN`, `ZH_BOB_TOKEN` | Distinct signed-in users; names are labels, identities come from Oracle |
| `ZH_EMBED_MODEL` | `PRISM.ALL_MINILM_L12_V2` |
| `ZH_RERANK_MODEL` | `ZH_OWNER.ZH_RERANKER` |
| `OLLAMA_BASE_URL` | `http://ollama:11434`; use `http://localhost:11434` outside the container network |
| `OLLAMA_MODEL` | `llama3.2` |

The store is `ZH_INCIDENTS`. Each kernel execution uses a unique run ID to
avoid colliding with earlier classroom runs. Rerun from a fresh kernel rather
than repeatedly executing write cells. Cleanup deletes only the two threads
created by the current run. Shared runbooks expire under the 30-day retention
policy; an instructor manages store/identity teardown separately.

## Validation and PR review

```bash
.venv/bin/python validate_notebooks.py
.venv/bin/python -m unittest discover -s tests -v
```

Static validation checks notebook format, syntax (including top-level await),
empty outputs, short cells, student/solution parity, and required 26.8 APIs.
Unit tests cover the reranker contract, bound SQL inputs, security-context
cleanup and rejection of unrelated failures in isolation checks. These checks
do **not** establish live database security or model quality.

For integration acceptance, execute the complete notebook on the provisioned
stack from a fresh kernel. Require model preflight, private-record readback,
empty cross-user search and SQL reads, rejected forged/global writes, rejected
no-context SQL, a completed extraction with stored records, graph/TTL checks,
the retrieval score table, compaction output, an actual LangChain recall tool
call, cross-session state recovery, blocked unapproved handover writes, recalled
procedural learning, and post-cleanup row/chunk counts. Record the database
RU, model versions and notebook commit with the run. An unavailable IAM token,
database or Ollama server is a missing prerequisite, never a passing test.

## Sources

- [OAMP 26.8 release notes][release]
- [OAMP Deep Data Security API][deepsec]
- [In-database embedding and model-role privileges][security]
- [OAMP reranker interface][models]
- [Database ONNX reranking parameters][rerank]
- [python-oracledb end-user security contexts][driver]
- [LangChain agent factory](https://reference.langchain.com/python/langchain/agents/factory/create_agent)
- [LangChain ChatOllama](https://reference.langchain.com/python/langchain-ollama/chat_models/ChatOllama)

[release]: https://docs.oracle.com/en/database/oracle/agent-memory/26.8/guide/whats-new.html
[security]: https://docs.oracle.com/en/database/oracle/agent-memory/26.8/guide/int-deep-data-security.html
[deepsec]: https://docs.oracle.com/en/database/oracle/agent-memory/26.8/guide/api/deep_data_security.html
[models]: https://docs.oracle.com/en/database/oracle/agent-memory/26.8/guide/api/models.html
[rerank]: https://docs.oracle.com/en/database/oracle/oracle-database/26/arpls/dbms_vector_chain1.html
[driver]: https://python-oracledb.readthedocs.io/en/latest/user_guide/connection_handling.html#end-user-security-contexts
[onnx]: https://docs.oracle.com/en/database/oracle/machine-learning/oml4py/2-23ai/mlpug/convert-pretrained-models-onnx-model-end-end-instructions.html
