-- ============================================================================
-- RAG to Agents Lab: Reset demo state between runs
-- ============================================================================
-- Run as: PRISM user
--
-- Example:
--   sqlplus prism/<password>@localhost:1521/FREEPDB1 @notebooks/rag_to_agents_reset.sql
--
-- Purpose:
--   The agent's remember(...) tool inserts an item into the OracleStore
--   every turn, and OracleSaver checkpoints every model step in the
--   thread. Across re-runs of the notebook those accumulate and make
--   recall() / recall_similar() return more (and eventually noisier) data
--   than the first run saw, and they cause the second turn of §5.10 to
--   pick up stale message history. This script wipes both surfaces so each
--   lab run starts from a clean slate.
--
--   Everything else the notebook uses (assets, districts, logs, reports,
--   findings, graph edges, DOCUMENT_CHUNKS with embeddings, vector indexes,
--   the ONNX DEMO_MODEL) is populated by the prep pipeline and does NOT
--   need to be reset between runs. This script deliberately does not touch
--   those.
--
-- Idempotent: safe to run when memory tables are already empty or absent.
-- ============================================================================

SET SERVEROUTPUT ON
SET VERIFY OFF
SET FEEDBACK OFF

PROMPT
PROMPT ============================================================================
PROMPT  RAG to Agents Lab: Reset demo state
PROMPT ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Long-term memory: OracleStore tables
-- ----------------------------------------------------------------------------
-- The notebook builds the store with table_suffix="bridge", so the tables
-- are STORE_BRIDGE (KV) and STORE_VECTORS_BRIDGE (embeddings). Truncating
-- the KV table cascades via foreign key to the vectors table.
-- ----------------------------------------------------------------------------

DECLARE
    v_count NUMBER := 0;
    v_exists NUMBER := 0;
BEGIN
    SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'STORE_BRIDGE';
    IF v_exists = 0 THEN
        DBMS_OUTPUT.PUT_LINE('STORE_BRIDGE does not exist yet. Run §5.4 of the notebook first.');
    ELSE
        SELECT COUNT(*) INTO v_count FROM store_bridge;
        DBMS_OUTPUT.PUT_LINE('STORE_BRIDGE rows before reset: ' || v_count);
        -- DELETE (not TRUNCATE) because TRUNCATE on a parent table with
        -- enabled FK constraints fails on Oracle. ON DELETE CASCADE on the
        -- vectors table FK takes care of STORE_VECTORS_BRIDGE for us.
        EXECUTE IMMEDIATE 'DELETE FROM store_bridge';
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('STORE_BRIDGE cleared (cascades to STORE_VECTORS_BRIDGE).');
    END IF;
END;
/

-- ----------------------------------------------------------------------------
-- 2. Short-term memory: OracleSaver checkpoint tables
-- ----------------------------------------------------------------------------
-- OracleSaver writes to CHECKPOINTS, CHECKPOINT_BLOBS, and CHECKPOINT_WRITES,
-- partitioned by thread_id. The notebook uses THREAD_ID = 'bridge-demo-001'
-- by default. Wiping just that thread keeps any other agents on this schema
-- intact. Change the literal below if you set a different THREAD_ID in
-- cell 0.4.
-- ----------------------------------------------------------------------------

DECLARE
    v_count NUMBER := 0;
    v_exists NUMBER := 0;
BEGIN
    SELECT COUNT(*) INTO v_exists FROM user_tables WHERE table_name = 'CHECKPOINTS';
    IF v_exists = 0 THEN
        DBMS_OUTPUT.PUT_LINE('CHECKPOINTS does not exist yet. Run §5.4 of the notebook first.');
    ELSE
        SELECT COUNT(*) INTO v_count
        FROM checkpoints WHERE thread_id = 'bridge-demo-001';
        DBMS_OUTPUT.PUT_LINE('CHECKPOINTS rows for bridge-demo-001 before reset: ' || v_count);
        EXECUTE IMMEDIATE 'DELETE FROM checkpoint_writes WHERE thread_id = ''bridge-demo-001''';
        EXECUTE IMMEDIATE 'DELETE FROM checkpoint_blobs  WHERE thread_id = ''bridge-demo-001''';
        EXECUTE IMMEDIATE 'DELETE FROM checkpoints       WHERE thread_id = ''bridge-demo-001''';
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Checkpoint tables cleared for thread bridge-demo-001.');
    END IF;
END;
/

PROMPT
PROMPT --- Verification ---

SELECT 'store_bridge'          AS table_name, COUNT(*) AS rows_after_reset FROM store_bridge
UNION ALL
SELECT 'store_vectors_bridge'  AS table_name, COUNT(*) AS rows_after_reset FROM store_vectors_bridge
UNION ALL
SELECT 'checkpoints (bridge-demo-001)' AS table_name, COUNT(*) AS rows_after_reset
    FROM checkpoints WHERE thread_id = 'bridge-demo-001';

PROMPT
PROMPT ============================================================================
PROMPT  rag_to_agents_reset: OK
PROMPT ============================================================================
PROMPT  Note: rerunning §5.4 of the notebook is no longer necessary to wipe
PROMPT  short-term memory — this script does it. Just re-run §5.8 onward.
PROMPT ============================================================================

SET FEEDBACK ON
