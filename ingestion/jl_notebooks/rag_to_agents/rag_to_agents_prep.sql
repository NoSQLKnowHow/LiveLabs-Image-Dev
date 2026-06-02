-- ============================================================================
-- RAG to Agents Lab: Prep Script
-- ============================================================================
-- Run as: PRISM user (the same schema loaded by schema-data/prism-setup.sql)
--
-- Example:
--   sqlplus prism/<password>@localhost:1521/FREEPDB1 @notebooks/rag_to_agents_prep.sql
--
-- Purpose:
--   Creates the optional hybrid vector index on DOCUMENT_CHUNKS used by the
--   notebook's RAG retrieval. This is the only object created here.
--
--   The agent's long-term memory and the LangGraph thread checkpointer are
--   both now backed by langgraph-oracledb, which creates and migrates its
--   own tables in §5.4 of the notebook on first run. No DBA work required
--   for those — see the notebook for details.
--
-- Prerequisites (run these FIRST, in order):
--   1. @schema-data/prism-setup.sql         (schema, tables, views, graph)
--   2. Load DEMO_MODEL ONNX embedding model (method depends on your environment)
--   3. python schema-data/prism-seed.py     (sample data)
--   4. python schema-data/prism-ingest.py   (chunk + embed narratives)
--   5. @schema-data/prism-indexes.sql       (HNSW vector index on DOCUMENT_CHUNKS)
--   6. @notebooks/rag_to_agents_prep.sql     (this script)
--
-- Idempotent: safe to re-run. Existing objects are dropped and recreated.
-- ============================================================================

SET SERVEROUTPUT ON
SET VERIFY OFF
SET FEEDBACK OFF

PROMPT
PROMPT ============================================================================
PROMPT  RAG to Agents Lab: Prep
PROMPT ============================================================================

-- ----------------------------------------------------------------------------
-- Hybrid vector index (optional)
-- ----------------------------------------------------------------------------
-- Best-effort: some Oracle AI Database 26ai environments do not have the
-- hybrid vector feature enabled, or it requires additional setup. If the
-- attempt fails, the notebook's search_incidents_semantic tool falls back to
-- vector-only search, so this is purely an enhancement.
-- ----------------------------------------------------------------------------

PROMPT
PROMPT [1/1] Attempting hybrid vector index on DOCUMENT_CHUNKS...

DECLARE
    e_already_exists EXCEPTION;
    PRAGMA EXCEPTION_INIT (e_already_exists, -955);  -- ORA-00955: name already used
BEGIN
    -- Drop prior version if present (idempotent)
    BEGIN
        EXECUTE IMMEDIATE 'DROP INDEX idx_chunks_hybrid';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -1418 AND SQLCODE != -942 THEN NULL; END IF;
    END;

    EXECUTE IMMEDIATE q'[
        CREATE HYBRID VECTOR INDEX idx_chunks_hybrid
            ON document_chunks(chunk_text)
            PARAMETERS('MODEL DEMO_MODEL')
    ]';

    DBMS_OUTPUT.PUT_LINE('        Hybrid vector index IDX_CHUNKS_HYBRID created.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('        Skipped (not available in this environment): ' ||
                             SUBSTR(SQLERRM, 1, 180));
        DBMS_OUTPUT.PUT_LINE('        Notebook will fall back to vector-only search.');
END;
/

-- ----------------------------------------------------------------------------
-- Verification
-- ----------------------------------------------------------------------------

PROMPT
PROMPT --- Verification ---

COLUMN object_name FORMAT A35
COLUMN object_type FORMAT A15
SELECT object_name, object_type
FROM user_objects
WHERE object_name IN ('IDX_CHUNKS_HYBRID')
ORDER BY object_type, object_name;

PROMPT
PROMPT ============================================================================
PROMPT  rag_to_agents_prep: OK
PROMPT ============================================================================
PROMPT  Notes:
PROMPT   - AGENT_MEMORY is no longer created here. The agent's long-term
PROMPT     memory is built by langgraph-oracledb's OracleStore inside the
PROMPT     notebook (cell §5.4) on first run.
PROMPT   - LangGraph thread checkpoints are managed by langgraph-oracledb's
PROMPT     OracleSaver, also from the notebook.
PROMPT  Next step: open notebooks/rag_to_agents_lab.ipynb and run Section 0.
PROMPT ============================================================================

SET FEEDBACK ON
