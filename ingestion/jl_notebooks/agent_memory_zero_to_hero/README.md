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
- Ollama serving `llama3.2` (the default 3B model) through both its native API
  and compatible `/v1` API, with an 8,192-token server context and sufficient
  inference memory.

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
| `OLLAMA_MODEL` | Default `llama3.2` |
| `ZH_DECLINE_HANDOVER` | `1` declines the optional save during unattended execution |

On a hosted notebook, `localhost` means the notebook server, not the learner's
laptop. The supplied endpoint must be reachable from that runtime.

The database cell calls `oracledb.create_pool(...)` directly. The small pool
supports background extraction and threaded tool reads. Inspection queries use fixed
workshop table names in the connected account and bind record/thread IDs.

### Model-client compatibility

Both clients use `llama3.2`, with temperature 0.7, top-p 0.8 and a maximum
generated response of 2,048 tokens. LangChain sends `num_ctx=8192`; OAMP uses
the server's context setting. No thinking-mode parameters are sent for this
model. Changing the model means checking native chat, tool calls and the
compatible API's structured output, not just whether the model loads.

The previous Qwen configuration used client-specific thinking controls.
Those controls have been removed for Llama 3.2; the prompts, sampling settings,
database embedding model and memory workflow remain the same for comparison.
An explicit `OLLAMA_MODEL` environment setting or `.env` entry overrides the
notebook default, so confirm the printed model name when you run the lab.

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

## Execution record and model comparison

The Llama 3.2 complete notebook executed **80 of 80 code cells without cell
exceptions** from a fresh kernel on 9 October 2026, run `3738399430`, in about
91 seconds (excluding the model download). Its actual outputs are saved in
`notebook_complete_ollama.ipynb`; the student notebook has empty outputs.
There is no separate executed notebook.

**The core inventory answer matched the previous Qwen run, but overall output
quality did not.** The comparison kept the case, prompts, sampling settings,
database embeddings and memory workflow unchanged. Only the selected model and
its client-specific thinking controls changed. These are two local observations,
not a controlled quality benchmark or a guarantee of repeatability.

| Observation | Qwen3.5 9B baseline, `22d0a021ed` | Llama 3.2, `3738399430` |
|---|---|---|
| Notebook execution | 80/80 cells | 80/80 cells; one handled tool-validation error remained visible in the trace |
| Compatible API and structured output | Passed | Passed |
| Bare LLM with both notes | 120 approved, PO-1048, not submitted | Same core facts |
| Fresh transient agent without case notes | Answered unknown | Invented 12 units and an approval reference of SOP-102 |
| Extraction checkpoints | Three proposal and two approval candidates | Two candidates per step; both processing checks passed |
| Extracted facts | Retained the proposal quantity and explicit no-order statement | Omitted the proposal quantity and explicit no-order statement from the candidate memories |
| Compact summary | Retained 80 proposed, 120 approved and no order submitted | Retained the two quantities, but omitted the explicit no-order statement |
| Reviewed history and fresh-session Oracle recall | Correct current fact and historical proposal | Same; the agent recalled 120 approved under PO-1048, not submitted |
| Memory-aware tool use | No error observations | Sent an invalid `report_reference` argument to `inspect_stock_report`; validation rejected it, and later recall still produced the correct answer |
| Procedure vector retrieval | Expected procedure in the top three for all three questions | Same; embedding model and database retrieval were unchanged |
| LLM pruning | Expected procedure retained in the top three | Same |
| Full handover | Core facts correct, cited IDs present in supplied evidence; 85 whitespace-separated words | Core facts correct, but one cited UUID was altered and the draft exceeded the under-120-word instruction (129 whitespace-separated words) |
| Reusable procedure | Recalled the reviewed checklist | Recalled it, but added extra workflow suggestions that are not approved policy |
| Human approval and cleanup | Unapproved write blocked; save declined; both case threads cleared | Same |

The Llama handover cited `9f089e83-eaf1-4077-a200-e12f6d6b6cb7`, whereas
the supplied source-message ID was `9f089e83-eaf1-4077-a200-e12f6a5b6cb7`.
The raw output is intentionally preserved. Correct business facts alone do not
make a citation or tool call valid. The explicit reviewed fact and source
messages remain essential when extraction or compaction omits information.

The unattended run declined the optional handover save, so its approved-write
branch was not exercised. Both run-specific threads ended with zero thread,
message, memory and chunk rows; shared procedures retain their existing TTL.
The local runner emitted a macOS process-inspection permission warning during
kernel shutdown after all cells completed. Outputs were saved successfully,
with no notebook error outputs.

Both runs used Python 3.13, LiteLLM 1.104.0, Ollama 0.40.0, OAMP 26.8.0,
Oracle AI Database Free 23.26.2.0.0 and `AGENT.ALL_MINILM_L12_V2` embeddings.
The local `llama3.2:latest` is a 3.2B-parameter Q4_K_M model, loaded with an
8,192-token context. Its digest is
`a80c4f17acd55265feec403c7aef86be0c25983ab279d83f3bcd3abbcb5b8b72`.
The Qwen baseline digest was
`d63f830f28d515fefea546f213fca7a75e9dd5176ef51a6deabc952d1c99a911`.
The baseline outputs remain in Git history at commit `1cac500`.

Focused ingestion-guard checks also passed after the model change: timeouts,
logged background errors and empty current-ingestion results cannot be masked
by older memories. Earlier checks separately exercised real SDK provider failure
and repeat-safe procedure seeding; those were not repeated as part of this model
comparison. Generated candidates and fluent answers still require review.

## References

- [Oracle Agent Memory 26.8 release notes](https://docs.oracle.com/en/database/oracle/agent-memory/26.8/guide/whats-new.html)
- [OAMP memory API](https://docs.oracle.com/en/database/oracle/agent-memory/26.8/guide/api/agentmemory.html)
- [OAMP model interfaces](https://docs.oracle.com/en/database/oracle/agent-memory/26.8/guide/api/models.html)
- [LangChain agent factory](https://reference.langchain.com/python/langchain/agents/factory/create_agent)
- [Ollama documentation](https://docs.ollama.com/)
- [Ollama Llama 3.2 model](https://ollama.com/library/llama3.2)
- [Ollama compatible API](https://docs.ollama.com/api/openai-compatibility)
