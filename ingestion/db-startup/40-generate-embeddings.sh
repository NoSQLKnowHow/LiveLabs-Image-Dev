#!/bin/bash
set -euo pipefail

# PRISM SQL*Plus vector ingestion pipeline.
# Converted from prism-ingest.py.
#
# Reads maintenance log narratives, inspection report summaries, and inspection
# finding descriptions, chunks them with DBMS_VECTOR_CHAIN.UTL_TO_CHUNKS,
# generates embeddings with VECTOR_EMBEDDING, and writes DOCUMENT_CHUNKS.
#
# Host example:
#   DBPASSWORD='...' DBCONNECTION='localhost:1521/freepdb1' ./32-ingest-data.sh
#
# DB container example:
#   DBPASSWORD='...' DBCONNECTION='localhost:1521/freepdb1' /opt/oracle/scripts/startup/32-ingest-data.sh

DBUSER="${DBUSER:-PRISM}"
DBPASSWORD="${DBPASSWORD:-${APP_DB_ADMIN_PWD:-${ORACLE_PWD:-Welcome202626ai}}}"
DBCONNECTION="${DBCONNECTION:-localhost:1521/freepdb1}"
MODEL_NAME="${MODEL_NAME:-ALL_MINILM_L12_V2}"
CHUNK_MAX_SIZE="${CHUNK_MAX_SIZE:-1000}"
CHUNK_OVERLAP="${CHUNK_OVERLAP:-100}"
CHUNK_SPLIT_BY="${CHUNK_SPLIT_BY:-sentence}"
BATCH_SIZE="${BATCH_SIZE:-50}"

DBUSER_UPPER="$(echo "${DBUSER}" | tr '[:lower:]' '[:upper:]')"
MODEL_NAME_UPPER="$(echo "${MODEL_NAME}" | tr '[:lower:]' '[:upper:]')"
ORACLE_IDENTIFIER_RE='^[A-Z][A-Z0-9_$#]*$'

if [[ -z "${DBPASSWORD}" ]]; then
  echo "DBPASSWORD, APP_DB_ADMIN_PWD, and ORACLE_PWD are all empty; cannot connect."
  exit 1
fi

if [[ ! "${DBUSER_UPPER}" =~ ${ORACLE_IDENTIFIER_RE} ]]; then
  echo "Invalid DBUSER value: ${DBUSER}"
  exit 1
fi

if [[ ! "${MODEL_NAME_UPPER}" =~ ${ORACLE_IDENTIFIER_RE} ]]; then
  echo "Invalid MODEL_NAME value: ${MODEL_NAME}"
  exit 1
fi

if [[ ! "${CHUNK_MAX_SIZE}" =~ ^[0-9]+$ || ! "${CHUNK_OVERLAP}" =~ ^[0-9]+$ || ! "${BATCH_SIZE}" =~ ^[0-9]+$ ]]; then
  echo "CHUNK_MAX_SIZE, CHUNK_OVERLAP, and BATCH_SIZE must be positive integers."
  exit 1
fi

if (( CHUNK_MAX_SIZE < 1 || BATCH_SIZE < 1 )); then
  echo "CHUNK_MAX_SIZE and BATCH_SIZE must be greater than zero."
  exit 1
fi

if [[ ! "${CHUNK_SPLIT_BY}" =~ ^[A-Za-z_]+$ ]]; then
  echo "Invalid CHUNK_SPLIT_BY value: ${CHUNK_SPLIT_BY}"
  exit 1
fi

echo "========================================================================"
echo "  PRISM: SQL*Plus Vector Ingestion Pipeline"
echo "========================================================================"
echo

sqlplus -s "${DBUSER}/${DBPASSWORD}@${DBCONNECTION}" <<SQL
whenever sqlerror exit sql.sqlcode rollback;
set define off
set verify off
set feedback on
set serveroutput on size unlimited

alter session set current_schema = ${DBUSER_UPPER};

declare
  c_model_name     constant varchar2(128) := '${MODEL_NAME_UPPER}';
  c_chunk_params   constant varchar2(4000) :=
    '{"max":${CHUNK_MAX_SIZE},"overlap":${CHUNK_OVERLAP},"split":"${CHUNK_SPLIT_BY}","normalize":"all"}';
  c_batch_size     constant pls_integer := ${BATCH_SIZE};

  l_model_count    number;
  l_source_count   number;
  l_total_chunks   number := 0;
  l_chunk_count    number;
  l_processed      number;
  l_total          number;
  l_started_at     timestamp := systimestamp;
  l_elapsed_secs   number;

  procedure assert_source_data is
  begin
    dbms_output.put_line('Source data counts:');

    select count(*) into l_source_count from maintenance_logs;
    dbms_output.put_line('  ' || rpad('maintenance_logs', 30) || lpad(l_source_count, 6) || ' rows');
    if l_source_count = 0 then
      raise_application_error(-20001, 'No source data found. Run the PRISM seed loader first.');
    end if;

    select count(*) into l_source_count from inspection_reports;
    dbms_output.put_line('  ' || rpad('inspection_reports', 30) || lpad(l_source_count, 6) || ' rows');

    select count(*) into l_source_count from inspection_findings;
    dbms_output.put_line('  ' || rpad('inspection_findings', 30) || lpad(l_source_count, 6) || ' rows');
  end;

  procedure chunk_and_embed(
    p_source_table in varchar2,
    p_source_id    in number,
    p_text         in clob,
    p_chunk_count  out number
  ) is
    l_chunk_text varchar2(4000);
  begin
    p_chunk_count := 0;

    if p_text is null or trim(dbms_lob.substr(p_text, 4000, 1)) is null then
      return;
    end if;

    for c in (
      select rownum as chunk_seq,
             coalesce(
               json_value(et.column_value, '\$.chunk_data' returning varchar2(4000) null on error),
               to_char(et.column_value)
             ) as chunk_text
        from table(
          dbms_vector_chain.utl_to_chunks(
            p_text,
            json(c_chunk_params)
          )
        ) et
    ) loop
      l_chunk_text := c.chunk_text;

      if l_chunk_text is null or trim(l_chunk_text) is null then
        continue;
      end if;

      execute immediate
        'insert into document_chunks (source_table, source_id, chunk_seq, chunk_text, embedding)
         values (:1, :2, :3, :4, vector_embedding(' || c_model_name || ' using :5 as data))'
        using p_source_table, p_source_id, c.chunk_seq, l_chunk_text, l_chunk_text;

      p_chunk_count := p_chunk_count + 1;
    end loop;
  end;

  procedure ingest_maintenance_logs is
  begin
    dbms_output.put_line(chr(10) || '--- Ingesting Maintenance Logs ---');

    select count(*)
      into l_total
      from maintenance_logs ml
     where not exists (
       select 1
         from document_chunks dc
        where dc.source_table = 'maintenance_logs'
          and dc.source_id = ml.log_id
     );

    dbms_output.put_line('  Found ' || l_total || ' logs to process.');
    l_processed := 0;
    l_total_chunks := 0;

    for r in (
      select log_id, narrative
        from maintenance_logs ml
       where not exists (
         select 1
           from document_chunks dc
          where dc.source_table = 'maintenance_logs'
            and dc.source_id = ml.log_id
       )
       order by log_id
    ) loop
      begin
        savepoint source_row;
        chunk_and_embed('maintenance_logs', r.log_id, to_clob(r.narrative), l_chunk_count);
        l_total_chunks := l_total_chunks + l_chunk_count;
        l_processed := l_processed + 1;

        if mod(l_processed, c_batch_size) = 0 then
          commit;
          dbms_output.put_line('  Processed ' || l_processed || '/' || l_total || ' logs (' || l_total_chunks || ' chunks so far)...');
        end if;
      exception
        when others then
          rollback to source_row;
          dbms_output.put_line('  ERROR processing log_id ' || r.log_id || ': ' || sqlerrm);
      end;
    end loop;

    commit;
    dbms_output.put_line('  Completed: ' || l_processed || ' logs, ' || l_total_chunks || ' chunks created.');
  end;

  procedure ingest_inspection_reports is
  begin
    dbms_output.put_line(chr(10) || '--- Ingesting Inspection Report Summaries ---');

    select count(*)
      into l_total
      from inspection_reports ir
     where ir.summary is not null
       and not exists (
         select 1
           from document_chunks dc
          where dc.source_table = 'inspection_reports'
            and dc.source_id = ir.report_id
       );

    dbms_output.put_line('  Found ' || l_total || ' report summaries to process.');
    l_processed := 0;
    l_total_chunks := 0;

    for r in (
      select report_id, summary
        from inspection_reports ir
       where ir.summary is not null
         and not exists (
           select 1
             from document_chunks dc
            where dc.source_table = 'inspection_reports'
              and dc.source_id = ir.report_id
         )
       order by report_id
    ) loop
      begin
        savepoint source_row;
        chunk_and_embed('inspection_reports', r.report_id, to_clob(r.summary), l_chunk_count);
        l_total_chunks := l_total_chunks + l_chunk_count;
        l_processed := l_processed + 1;

        if mod(l_processed, c_batch_size) = 0 then
          commit;
          dbms_output.put_line('  Processed ' || l_processed || '/' || l_total || ' reports (' || l_total_chunks || ' chunks so far)...');
        end if;
      exception
        when others then
          rollback to source_row;
          dbms_output.put_line('  ERROR processing report_id ' || r.report_id || ': ' || sqlerrm);
      end;
    end loop;

    commit;
    dbms_output.put_line('  Completed: ' || l_processed || ' reports, ' || l_total_chunks || ' chunks created.');
  end;

  procedure ingest_inspection_findings is
  begin
    dbms_output.put_line(chr(10) || '--- Ingesting Inspection Finding Descriptions ---');

    select count(*)
      into l_total
      from inspection_findings inf
     where inf.description is not null
       and not exists (
         select 1
           from document_chunks dc
          where dc.source_table = 'inspection_findings'
            and dc.source_id = inf.finding_id
       );

    dbms_output.put_line('  Found ' || l_total || ' finding descriptions to process.');
    l_processed := 0;
    l_total_chunks := 0;

    for r in (
      select finding_id, description
        from inspection_findings inf
       where inf.description is not null
         and not exists (
           select 1
             from document_chunks dc
            where dc.source_table = 'inspection_findings'
              and dc.source_id = inf.finding_id
         )
       order by finding_id
    ) loop
      begin
        savepoint source_row;
        chunk_and_embed('inspection_findings', r.finding_id, to_clob(r.description), l_chunk_count);
        l_total_chunks := l_total_chunks + l_chunk_count;
        l_processed := l_processed + 1;

        if mod(l_processed, c_batch_size) = 0 then
          commit;
          dbms_output.put_line('  Processed ' || l_processed || '/' || l_total || ' findings (' || l_total_chunks || ' chunks so far)...');
        end if;
      exception
        when others then
          rollback to source_row;
          dbms_output.put_line('  ERROR processing finding_id ' || r.finding_id || ': ' || sqlerrm);
      end;
    end loop;

    commit;
    dbms_output.put_line('  Completed: ' || l_processed || ' findings, ' || l_total_chunks || ' chunks created.');
  end;
begin
  dbms_output.put_line('Connecting to Oracle database...');
  dbms_output.put_line('  Connected.');

  dbms_output.put_line(chr(10) || 'Verifying embedding model...');
  select count(*)
    into l_model_count
    from all_mining_models
   where model_name = c_model_name;

  if l_model_count = 0 then
    raise_application_error(-20002, 'Embedding model ' || c_model_name || ' not found. Load the ONNX model first.');
  end if;
  dbms_output.put_line('  Model ''' || c_model_name || ''' found.');

  assert_source_data;

  ingest_maintenance_logs;
  ingest_inspection_reports;
  ingest_inspection_findings;

  l_elapsed_secs := extract(day from (systimestamp - l_started_at)) * 86400
                 + extract(hour from (systimestamp - l_started_at)) * 3600
                 + extract(minute from (systimestamp - l_started_at)) * 60
                 + extract(second from (systimestamp - l_started_at));

  dbms_output.put_line(chr(10) || '--- Ingestion Summary ---');
  for r in (
    select source_table, count(*) chunk_count
      from document_chunks
     group by source_table
     order by source_table
  ) loop
    dbms_output.put_line('  ' || rpad(r.source_table, 30) || lpad(r.chunk_count, 6) || ' chunks');
  end loop;

  select count(*) into l_total from document_chunks;
  dbms_output.put_line('  ' || rpad('TOTAL', 30) || lpad(l_total, 6) || ' chunks');
  dbms_output.put_line(chr(10) || '  Elapsed time: ' || to_char(round(l_elapsed_secs, 1)) || ' seconds');
  dbms_output.put_line('Vector ingestion complete.');
exception
  when others then
    rollback;
    raise;
end;
/

exit;
SQL

echo
echo "========================================================================"
echo "  Vector ingestion complete."
echo "  Next step: create the HNSW vector index."
echo "========================================================================"
