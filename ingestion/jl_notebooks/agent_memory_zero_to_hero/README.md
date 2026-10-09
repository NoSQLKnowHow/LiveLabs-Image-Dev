# Agent Memory: Introduction to context and memory engineering

Build a **memory aware agent** for a familiar ecommerce task: help the next
inventory planner understand an unfinished restocking decision.

Alice proposes buying 80 ceramic mugs. The manager later approves 120 under
request PO-1048, but **no supplier order has been submitted**. A new shift
needs the latest decision, the supporting evidence and the outstanding work.
Approval, ordering and receiving stock are separate events.

Start with the [student notebook](notebook_student_ollama.ipynb), or freely
consult the [complete notebook](notebook_complete_ollama.ipynb). **This is not
a coding test.** Work through the **17 numbered TODOs**, use the expandable
hints and explain what each step adds. Every code cell has explanatory Markdown
immediately before it. Shared explanations and diagrams match between editions;
the complete notebook contains the worked code and actual execution outputs.

Allow 150–180 minutes, including discussion and local model time.

## Learning journey

| Part | What students build or understand |
|---|---|
| 1 | The human inventory workflow, missing information and business friction |
| 2 | Agent-stack layers, working context and durable memory roles |
| 3 | The provided LiveLabs services, inventory case and Ollama model |
| 4 | A bare LLM with case notes, then a fresh call without them |
| 5 | A tool-using agent loop that does not yet retain conversation |
| 6 | Oracle messages, extracted knowledge, reviewed facts and reusable procedures |
| 7 | The same loop with durable recall, offloading and cross-session continuity |
| 8 | Ordered vector-search tables, pruning and curated working context |
| 9 | Human review of a write, reusable lessons, expiration and scoped cleanup |

The notebook keeps the model and business question consistent while adding
capabilities. A response table compares the actual outputs from the bare LLM,
transient agent and memory aware agent. Later cells distinguish automatically
extracted candidates from reviewed facts, and a case-specific handover from
a reusable procedure.

**Context engineering** systematically selects task-relevant instructions,
evidence and observations for the LLM's finite context window. **Memory
engineering** designs how the application retains, reuses, refines and recalls
experience across turns and sessions. Working memory is the current context;
episodic, semantic and procedural memory are durable sources for rebuilding it.

### Diagrams

Editable SVG files live in `images/` and are also embedded in both notebooks
for offline display:

- [Build stages](images/learning_stages.svg): four technical views with labelled request, response and durable-memory flows.
- [Manual business process](images/inventory_process.svg): people and documents, before agents.
- [Reference architecture](images/reference_architecture.svg): the finished system.
- [Bare LLM context gap](images/llm_context_gap.svg): evidence present versus absent.
- [Agent loop](images/agent_loop.svg): choose, execute, observe and repeat.
- [Memory lifecycle](images/memory_lifecycle.svg): retain, extract, review and recall.
- [User/thread relationships](images/user_thread_scopes.svg): case and shared-procedure scopes.

## Oracle LiveLabs delivery

Open the student notebook in the workshop's provided notebook runtime and work
through the Parts in order. The complete edition contains the worked examples
and saved outputs. Learners do not install packages, create kernels or download
models as part of this notebook.

### Resources supplied by the workshop

The LiveLabs image and launch instructions must provide:

- The notebook folder, `inventory_data.json` and `images/`, with the folder as
  the notebook's working directory; no full GitHub checkout is needed.
- Python 3.13 and the dependencies in `requirements.txt`, including
  OAMP 26.8.0, python-oracledb 4.0.2, LangChain 1.4.0,
  langchain-ollama 1.1.0 and pandas 2.3.3.
- A dedicated Oracle workshop account and an imported 384-dimensional
  embedding model with a 256-token input limit.
- Ollama serving `qwen3.5:9b` through both its native API and compatible
  `/v1` API, with an 8,192-token server context and sufficient inference memory.

This is the delivery contract for the hosted workshop, not a claim that the
notebook provisions those services. The local execution record below verifies
the notebook against the available rehearsal services.

### Supplied connection settings

The notebook reads the session's environment variables and, when supplied,
the companion `.env` file without overriding existing variables. Keep
credentials out of notebook source and outputs.

| Variable | Purpose / default |
|---|---|
| `ZH_DB_USER` | Dedicated workshop account; default `ZH_LAB` |
| `ZH_DB_PASSWORD` | Required workshop password, supplied to the runtime |
| `ZH_DB_DSN` | Database host, port and service; default `aidbfree:1521/FREEPDB1` |
| `ZH_EMBED_MODEL` | Imported model; default `PRISM.ALL_MINILM_L12_V2` |
| `OLLAMA_BASE_URL` | Supplied model-service URL; default `http://localhost:11434` |
| `OLLAMA_MODEL` | Default `qwen3.5:9b` |
| `ZH_DECLINE_HANDOVER` | `1` declines the optional save during unattended execution |

On a hosted notebook, `localhost` means the notebook server, not the learner's
laptop. The supplied endpoint must be reachable from that runtime.

The database cell calls `oracledb.create_pool(...)` directly. The small pool
supports background extraction and threaded tool reads. Inspection queries use fixed
workshop table names in the connected account and bind record/thread IDs.

### Model-client compatibility

LangChain uses `reasoning=False`. OAMP passes
`extra_body={"reasoning_effort": "none"}` to Ollama's compatible endpoint.
Both request non-thinking output and cap generated responses at 2,048 tokens.
LangChain also sends `num_ctx=8192`; OAMP uses the server's context setting.

The reported structured-request failure was reproduced in the selected
Python environment with LiteLLM **1.100.0**: its parameter validation rejected
top-level `reasoning_effort` for `openai/qwen3.5:9b` before contacting Ollama.
The earlier successful rehearsal used LiteLLM **1.104.0**. Passing the option
through `extra_body` succeeded with the same model and server in 1.100.0;
no package upgrade or global parameter-dropping switch was needed.

OAMP uses `trust_env=False` for the workshop's direct connection. This does
not disable TLS verification. A hosted deployment requiring a proxy or
custom CA must have its connection policy supplied accordingly.

Embeddings and vector retrieval run in Oracle; generation, extraction,
summarization and pruning use Ollama. No paid model API key is required.
Generated wording can vary, so learners still review the actual evidence
and output rather than treating successful execution as proof of correctness.

## OAMP 26.8 capabilities students exercise

| Capability | Visible outcome |
|---|---|
| Background extraction | Check SDK errors and unsuccessful operations, then require fresh memories for each ingestion |
| Post-extraction linking | Separate inferred relationships from explicit review |
| Memory evolution and graph search | Current approval supersedes a historical proposal |
| Structured message content | Read `TextContent.text` to recover source messages |
| Record/thread listing | Show stored procedures and recover a conversation |
| Bounded vector retrieval | Preserve returned order in pandas tables |
| LLM pruning | Compare returned evidence with the unpruned result |
| Context cards and summaries | Budget relevant records separately from the rest of the card and final prompt |
| Observability | Count operation events without recording private content |
| Retention and cleanup | Contrast expiration with removal of scoped live rows |

## Boundaries and lifecycle

Background waits include failed jobs. The notebook's per-note checkpoint watches
SDK error logs and unsuccessful API completion events, and requires memories
carrying a new `capture_id` and a `capture_step` label. Earlier records cannot
satisfy a later ingestion check. The listener and error handler are removed even
on exceptions. These are local processing checks, not a distributed job-status
service or proof that extracted claims are true. Failed ingestion can leave a
stored source message or partial records.

For context cards, `token_budget=1600` limits the estimated tokens of formatted
relevant records only. Recent messages, summary context, instructions, the
question and the answer allowance need additional space in the model's context
window; the complete card or final prompt can exceed 1,600 tokens.

Alice and Bob are application labels, not database identities. Both clients use
one dedicated account. Their user/thread filters select evidence; they do not
provide multi-user authorization. Use synthetic data and preferably a separate
schema per participant.

The agent has read-only tools. A host-controlled human-review gate can save the
**fuller handover draft from Part 8**, but cannot submit a supplier order or
adjust stock. An unattended run declines that save; the approved-write branch
is not automatically exercised. A production implementation needs authenticated
approvers, durable authorization, idempotency and independently retained audit
records.

Persisting conversation and workflow metadata is not a crash-resumable
LangGraph checkpoint or an exactly-once execution guarantee. Reusing a reviewed
procedure updates retrievable knowledge, not the model's weights.

Each fresh kernel creates a unique run ID. Cleanup targets only that run's two
case threads and their dependent rows/chunks. Shared procedures remain with a
30-day TTL. Zero scoped live rows does not certify erasure from backups,
replicas, logs or storage media.

The procedure-seeding cell can be repeated with the same `RUN_ID`: it rereads
that run's saved procedure IDs, reuses existing records and inserts only missing
ones. It does not overwrite approved text or renew existing records' retention.
This protects sequential cell reruns, not concurrent writers, and does not make
every other write cell restartable. For a fresh full lab run, start again from
the configuration cell rather than regenerating `RUN_ID` midway through a case.

## Execution record

The complete notebook executed **80 of 80 code cells without cell exceptions**
from a fresh kernel on 9 October 2026, run `22d0a021ed`. All execution counts and
actual outputs are saved in `notebook_complete_ollama.ipynb`. The student notebook
retains empty outputs and there is no separate executed notebook.

Focused checks verified that the ingestion checkpoint rejects a timeout, a
logged background error and an empty extraction even when older memories exist.
A real SDK check used a deliberately unavailable model to trigger a provider
failure: the failed-operation event was detected, and the earlier memory could
not make the new ingestion pass. Only that check's temporary thread and synthetic
records were removed afterward.

The local runner reported a macOS process-inspection permission warning during
kernel shutdown, after all cells completed. It did not prevent output saving;
there are no notebook error outputs.

Earlier separate seed-cell checks replayed the reported duplicate-ID run twice
with zero inserts and unchanged records. A temporary partial seed with one existing procedure
added exactly three missing procedures; another replay added none. Only those
temporary check records were removed afterward; existing learner records stayed intact.

This execution used Python 3.13, LiteLLM 1.104.0 and the corrected provider-body
setting. It used Qwen3.5 9B through Ollama 0.40.0, OAMP 26.8.0,
Oracle AI Database Free 23.26.2.0.0 and `AGENT.ALL_MINILM_L12_V2` for
in-database embeddings. The model digest was
`d63f830f28d515fefea546f213fca7a75e9dd5176ef51a6deabc952d1c99a911`.

| Saved observation | Result |
|---|---|
| Compatible API and structured output | Both succeeded from the fresh kernel |
| Memory aware agent and fresh-session recall | Both answered 120 approved under PO-1048, no supplier order submitted |
| Per-ingestion extraction checkpoints | Persisted three proposal candidates and two approval candidates with distinct capture IDs; both checks passed without reported SDK failures |
| Extraction and summary | Captured 80 proposed versus 120 approved, with no order submitted; the automatically extracted old proposal was invalid in this run, while the explicit reviewed pair independently demonstrates supersession |
| Linked history table | Displayed the valid 120-unit approval, its supersedes relationship and the invalid historical 80-unit proposal |
| Procedure vector search | The expected procedure appeared in the first three results for all three sample questions |
| Full handover draft | Preserved 120 approved under PO-1048 and no order submitted; left the action owner unconfirmed and identified missing stock level, supplier ETA and submission timing |
| Bare model and transient agent without case evidence | Both answered unknown rather than inventing the quantity, approval request or order status |
| Human approval gate | Blocked the unapproved write and declined the optional save; the approved branch was not exercised |
| Procedural recall | Returned the reviewed checklist in the later session without copying PO-1048 |
| Cleanup | Both current run threads had zero remaining thread, message, memory and chunk rows |

These are observations from one run, not guarantees of model accuracy or
production retrieval quality. The notebooks retain the actual answers for
inspection, including mistakes, rather than replacing them with idealized text.

## References

- [Oracle Agent Memory 26.8 release notes](https://docs.oracle.com/en/database/oracle/agent-memory/26.8/guide/whats-new.html)
- [OAMP memory API](https://docs.oracle.com/en/database/oracle/agent-memory/26.8/guide/api/agentmemory.html)
- [OAMP model interfaces](https://docs.oracle.com/en/database/oracle/agent-memory/26.8/guide/api/models.html)
- [LangChain agent factory](https://reference.langchain.com/python/langchain/agents/factory/create_agent)
- [Ollama documentation](https://docs.ollama.com/)
- [Ollama compatible API](https://docs.ollama.com/api/openai-compatibility)
