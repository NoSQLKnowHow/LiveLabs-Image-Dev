#!/bin/bash
set -euo pipefail

# PRISM final startup verification.
#
# Confirms the workshop database has the expected converged-database surfaces
# before learners open the notebooks.

DBUSER="${DBUSER:-PRISM}"
DBPASSWORD="${DBPASSWORD:-${APP_DB_ADMIN_PWD:-${ORACLE_PWD:-Welcome202626ai}}}"
DBCONNECTION="${DBCONNECTION:-localhost:1521/freepdb1}"
MODEL_NAME="${MODEL_NAME:-ALL_MINILM_L12_V2}"

DBUSER_UPPER="$(echo "${DBUSER}" | tr '[:lower:]' '[:upper:]')"
MODEL_NAME_UPPER="$(echo "${MODEL_NAME}" | tr '[:lower:]' '[:upper:]')"

if [[ -z "${DBPASSWORD}" ]]; then
  echo "DBPASSWORD, APP_DB_ADMIN_PWD, ORACLE_PWD, and the default password fallback are all empty; cannot connect."
  exit 1
fi

echo "========================================================================"
echo "  PRISM: Final Build Verification"
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
  l_count    number;
  l_failures number := 0;

  procedure check_min_count(p_label in varchar2, p_sql in varchar2, p_min_count in number) is
  begin
    execute immediate p_sql into l_count;
    if l_count >= p_min_count then
      dbms_output.put_line('  OK   ' || rpad(p_label, 42) || l_count);
    else
      dbms_output.put_line('  FAIL ' || rpad(p_label, 42) || l_count || ' < ' || p_min_count);
      l_failures := l_failures + 1;
    end if;
  end;

  procedure check_exists(p_label in varchar2, p_sql in varchar2) is
  begin
    check_min_count(p_label, p_sql, 1);
  end;
begin
  dbms_output.put_line('Checking PRISM relational seed data...');
  check_min_count('DISTRICTS rows', 'select count(*) from districts', 7);
  check_min_count('INFRASTRUCTURE_ASSETS rows', 'select count(*) from infrastructure_assets', 28);
  check_min_count('ASSET_CONNECTIONS rows', 'select count(*) from asset_connections', 35);
  check_min_count('OPERATIONAL_PROCEDURES rows', 'select count(*) from operational_procedures', 9);
  check_min_count('MAINTENANCE_LOGS rows', 'select count(*) from maintenance_logs', 311);
  check_min_count('INSPECTION_REPORTS rows', 'select count(*) from inspection_reports', 61);
  check_min_count('INSPECTION_FINDINGS rows', 'select count(*) from inspection_findings', 225);

  dbms_output.put_line(chr(10) || 'Checking spatial data...');
  check_min_count('Asset point locations', 'select count(*) from infrastructure_assets where latitude is not null and longitude is not null and location is not null', 28);
  check_min_count('District boundaries', 'select count(*) from districts where center_latitude is not null and center_longitude is not null and boundary is not null', 7);
  check_exists('IDX_ASSETS_LOCATION', 'select count(*) from user_indexes where index_name = ''IDX_ASSETS_LOCATION''');
  check_exists('IDX_DISTRICTS_BOUNDARY', 'select count(*) from user_indexes where index_name = ''IDX_DISTRICTS_BOUNDARY''');

  dbms_output.put_line(chr(10) || 'Checking vector data...');
  check_exists('Embedding model ${MODEL_NAME_UPPER}', 'select count(*) from user_mining_models where model_name = ''${MODEL_NAME_UPPER}''');
  check_min_count('DOCUMENT_CHUNKS rows', 'select count(*) from document_chunks', 1);
  check_min_count('Chunk source coverage', 'select count(distinct source_table) from document_chunks where source_table in (''maintenance_logs'', ''inspection_reports'', ''inspection_findings'', ''operational_procedures'')', 4);
  check_exists('IDX_CHUNK_EMBEDDING', 'select count(*) from user_indexes where index_name = ''IDX_CHUNK_EMBEDDING''');

  dbms_output.put_line(chr(10) || 'Checking graph and helper views...');
  check_exists('CITYPULSE_GRAPH object', 'select count(*) from user_objects where object_name = ''CITYPULSE_GRAPH''');
  check_exists('INSPECTION_REPORT_DV view', 'select count(*) from user_views where view_name = ''INSPECTION_REPORT_DV''');
  check_exists('V_ASSET_SPECS_SUMMARY view', 'select count(*) from user_views where view_name = ''V_ASSET_SPECS_SUMMARY''');
  check_exists('V_OPERATIONAL_PROCEDURE_DOCUMENTS view', 'select count(*) from user_views where view_name = ''V_OPERATIONAL_PROCEDURE_DOCUMENTS''');
  check_exists('V_OPERATIONAL_PROCEDURE_SUMMARY view', 'select count(*) from user_views where view_name = ''V_OPERATIONAL_PROCEDURE_SUMMARY''');
  check_exists('V_CHUNKS_UNIFIED view', 'select count(*) from user_views where view_name = ''V_CHUNKS_UNIFIED''');
  check_exists('V_PRISM_MODEL_MAP view', 'select count(*) from user_views where view_name = ''V_PRISM_MODEL_MAP''');

  if l_failures > 0 then
    insert into prism_build_log (step_name, status, detail)
    values ('50-verify-prism-build', 'FAILURE', l_failures || ' verification checks failed.');
    commit;
    raise_application_error(-20050, l_failures || ' PRISM build verification checks failed.');
  end if;

  insert into prism_build_log (step_name, status, detail)
  values ('50-verify-prism-build', 'SUCCESS', 'All PRISM build verification checks passed.');
  commit;

  dbms_output.put_line(chr(10) || 'PRISM build verification complete.');
exception
  when others then
    rollback;
    begin
      insert into prism_build_log (step_name, status, detail)
      values ('50-verify-prism-build', 'FAILURE', substr(sqlerrm, 1, 4000));
      commit;
    exception
      when others then
        null;
    end;
    raise;
end;
/

exit;
SQL

echo
echo "========================================================================"
echo "  PRISM build verification complete."
echo "========================================================================"
