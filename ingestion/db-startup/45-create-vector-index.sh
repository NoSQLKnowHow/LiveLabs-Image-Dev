#!/bin/bash
set -euo pipefail

export DBPASSWORD="${APP_DB_ADMIN_PWD:-${ORACLE_PWD:-Welcome202626ai}}"
export DBUSER="$(echo "prism" | tr '[:lower:]' '[:upper:]')"
export DBCONNECTION="${DBCONNECTION:-localhost:1521/freepdb1}"

if [[ -z "${DBPASSWORD}" ]]; then
  echo "DBPASSWORD, APP_DB_ADMIN_PWD, ORACLE_PWD, and the default password fallback are all empty; cannot connect."
  exit 1
fi

# Set the vector memory size to 1GB so we can create a vector index.
sqlplus -s / as sysdba <<'EOF'

ALTER SESSION SET CONTAINER = CDB$ROOT;

ALTER SYSTEM SET vector_memory_size = 1G SCOPE = SPFILE;

SHUTDOWN IMMEDIATE;
STARTUP;

SHOW PARAMETER vector_memory_size;

exit;
EOF

# Create vector index on embeddings in DOCUMENT_CHUNKS if it does not exist already.
sqlplus -s ${DBUSER}/${DBPASSWORD}@${DBCONNECTION} <<SQL
whenever sqlerror exit sql.sqlcode;
SET DEFINE OFF
SET SERVEROUTPUT ON

ALTER SESSION SET CURRENT_SCHEMA = ${DBUSER};

PROMPT     Checking HNSW vector index on DOCUMENT_CHUNKS...

declare
  l_index_count number := 0;
begin
  select count(*)
    into l_index_count
    from user_indexes
   where index_name = 'IDX_CHUNK_EMBEDDING';

  if l_index_count = 0 then
    execute immediate '
      CREATE VECTOR INDEX idx_chunk_embedding
          ON document_chunks(embedding)
          ORGANIZATION INMEMORY NEIGHBOR GRAPH
          DISTANCE COSINE
          WITH TARGET ACCURACY 95';
    dbms_output.put_line('Vector index IDX_CHUNK_EMBEDDING created.');
  else
    dbms_output.put_line('Vector index IDX_CHUNK_EMBEDDING already exists; skipping create.');
  end if;
end;
/

insert into prism_build_log (step_name, status, detail)
values ('45-create-vector-index', 'SUCCESS', 'HNSW vector index IDX_CHUNK_EMBEDDING is present.');

commit;

exit;
SQL
