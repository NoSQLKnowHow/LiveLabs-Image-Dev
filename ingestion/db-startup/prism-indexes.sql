-- ============================================================================
-- PRISM: Post-Ingestion Index Script
-- ============================================================================
-- Run as: SYS AS SYSDBA (Oracle Free Docker) or ADMIN (on ADB)
-- Run after: prism-seed.py AND prism-ingest.py
-- Purpose: Creates the HNSW vector index on document_chunks after data
--          has been loaded and vectorized.
--
-- Instructions: Edit the DEFINE values below before running.
--               These should match the values used in prism-setup.sql.
-- ============================================================================

PROMPT
PROMPT ============================================================================
PROMPT  PRISM: Post-Ingestion Index Creation
PROMPT ============================================================================

PROMPT
PROMPT [2/3] Creating HNSW vector index on DOCUMENT_CHUNKS...

CREATE VECTOR INDEX idx_chunk_embedding
    ON document_chunks(embedding)
    ORGANIZATION INMEMORY NEIGHBOR GRAPH
    DISTANCE COSINE
    WITH TARGET ACCURACY 95;

PROMPT         Vector index IDX_CHUNK_EMBEDDING created.

-- ----------------------------------------------------------------------------
-- 3. Verification
-- ----------------------------------------------------------------------------

PROMPT
PROMPT [3/3] Verifying...

PROMPT
PROMPT Vector index:

SELECT index_name, index_type FROM user_indexes WHERE index_name = 'IDX_CHUNK_EMBEDDING';

PROMPT
PROMPT Chunk counts by source:

SELECT source_table, COUNT(*) AS chunk_count FROM document_chunks GROUP BY source_table;

PROMPT
PROMPT ============================================================================
PROMPT  Vector index created successfully.
PROMPT  Prism is ready to use.
PROMPT ============================================================================
PROMPT
