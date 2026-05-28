#!/bin/bash
set -euo pipefail

export DBPASSWORD="${APP_DB_ADMIN_PWD:-${ORACLE_PWD:-}}"
export DBUSER="$(echo "prism" | tr '[:lower:]' '[:upper:]')"
export DBCONNECTION="aidbfree:1521/freepdb1"

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
