#!/bin/bash
set -euo pipefail

export DBPASSWORD="${APP_DB_ADMIN_PWD:-${ORACLE_PWD:-}}"
export DBUSER="$(echo "prism" | tr '[:lower:]' '[:upper:]')"
export DBCONNECTION="aidbfree:1521/freepdb1"

# Set the vector memory size to 1GB so we can create a vector index.
sqlplus -s / as sysdba <<'EOF'

ALTER SESSION SET CONTAINER = CDB$ROOT;

ALTER SYSTEM SET vector_memory_size = 1G SCOPE = SPFILE;

SHUTDOWN IMMEDIATE;
STARTUP;

SHOW PARAMETER vector_memory_size;
/

exit;
EOF

# Create vector index on new vector embeddings in DOCUMENTS_CHUNKS table.
sqlplus ${DBUSER}/${DBPASSWORD}@${DBCONNECTION} <<SQL
whenever sqlerror exit sql.sqlcode;
SET DEFINE OFF
SET SERVEROUTPUT ON

ALTER SESSION SET CONTAINER = FREEPDB1;

ALTER SESSION SET CURRENT_SCHEMA = ${DBUSER};

PROMPT     Creating HNSW vector index on DOCUMENT_CHUNKS...

CREATE VECTOR INDEX idx_chunk_embedding
    ON document_chunks(embedding)
    ORGANIZATION INMEMORY NEIGHBOR GRAPH
    DISTANCE COSINE
    WITH TARGET ACCURACY 95;

PROMPT  Vector index IDX_CHUNK_EMBEDDING created.
/

exit;
SQL
