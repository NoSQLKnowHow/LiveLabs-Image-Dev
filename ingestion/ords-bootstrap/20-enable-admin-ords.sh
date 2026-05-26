#!/bin/bash
set -euo pipefail

DBHOST="${DBHOST:-aidbfree}"
DBPORT="${DBPORT:-1521}"
DBSERVICE="${DBSERVICENAME:-FREEPDB1}"
ADMIN_USER="${APP_DB_ADMIN_USER:-ADMIN}"
BASE_PATH="${APP_DB_ADMIN_BASE_PATH:-admin}"
DB_PWD="${ORACLE_PWD:-${APP_DB_ADMIN_PWD:-}}"

if [[ -z "${DB_PWD}" ]]; then
  echo "ORACLE_PWD/APP_DB_ADMIN_PWD is empty; cannot enable ORDS for ${ADMIN_USER}."
  exit 1
fi

if [[ ! "${ADMIN_USER}" =~ ^[A-Za-z][A-Za-z0-9_$#]*$ ]]; then
  echo "Invalid APP_DB_ADMIN_USER value: ${ADMIN_USER}"
  exit 1
fi

if [[ ! "${BASE_PATH}" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "Invalid APP_DB_ADMIN_BASE_PATH value: ${BASE_PATH}"
  exit 1
fi

ADMIN_USER_UPPER="$(echo "${ADMIN_USER}" | tr '[:lower:]' '[:upper:]')"
CONNECT_STRING="//${DBHOST}:${DBPORT}/${DBSERVICE}"

wait_for_db() {
  local retries=60
  local sleep_seconds=5
  local i

  for ((i = 1; i <= retries; i++)); do
    if sql -s "sys/${DB_PWD}@${CONNECT_STRING} as sysdba" <<'SQL' >/dev/null 2>&1
whenever sqlerror exit 1;
select 1 from dual;
exit;
SQL
    then
      return 0
    fi
    sleep "${sleep_seconds}"
  done

  return 1
}

wait_for_ords_admin_package() {
  local retries=120
  local sleep_seconds=5
  local i
  local result
  local count

  for ((i = 1; i <= retries; i++)); do
    result="$(sql -s "sys/${DB_PWD}@${CONNECT_STRING} as sysdba" <<'SQL' 2>/dev/null
set heading off feedback off pages 0 verify off echo off termout off
alter session set container = FREEPDB1;
select count(*)
  from dba_objects
 where owner = 'ORDS_METADATA'
   and object_name = 'ORDS_ADMIN'
   and object_type = 'PACKAGE';
exit;
SQL
)"
    count="$(echo "${result}" | awk '/^[[:space:]]*[0-9]+[[:space:]]*$/ {gsub(/[[:space:]]/, "", $0); print $0; exit}')"
    if [[ "${count:-}" == "1" ]]; then
      return 0
    fi
    sleep "${sleep_seconds}"
  done

  return 1
}

wait_for_admin_user() {
  local retries=120
  local sleep_seconds=5
  local i
  local result
  local count

  for ((i = 1; i <= retries; i++)); do
    result="$(sql -s "sys/${DB_PWD}@${CONNECT_STRING} as sysdba" <<SQL 2>/dev/null
set heading off feedback off pages 0 verify off echo off termout off
alter session set container = FREEPDB1;
select count(*)
  from dba_users
 where username = '${ADMIN_USER_UPPER}';
exit;
SQL
)"
    count="$(echo "${result}" | awk '/^[[:space:]]*[0-9]+[[:space:]]*$/ {gsub(/[[:space:]]/, "", $0); print $0; exit}')"
    if [[ "${count:-}" == "1" ]]; then
      return 0
    fi
    sleep "${sleep_seconds}"
  done

  return 1
}

if ! wait_for_db; then
  echo "Database did not become reachable at ${CONNECT_STRING} in time."
  exit 1
fi

if ! wait_for_ords_admin_package; then
  echo "ORDS_ADMIN package was not found in FREEPDB1; ORDS may not be initialized."
  exit 1
fi

if ! wait_for_admin_user; then
  echo "Database user ${ADMIN_USER_UPPER} was not found in FREEPDB1 in time."
  exit 1
fi

sql -s "sys/${DB_PWD}@${CONNECT_STRING} as sysdba" <<SQL
whenever sqlerror exit sql.sqlcode;
set define off
set serveroutput on

alter session set container = FREEPDB1;

begin
  ords_admin.enable_schema(
    p_enabled => true,
    p_schema => '${ADMIN_USER_UPPER}',
    p_url_mapping_type => 'BASE_PATH',
    p_url_mapping_pattern => '${BASE_PATH}',
    p_auto_rest_auth => true
  );
  commit;
  dbms_output.put_line('ORDS enabled for schema ${ADMIN_USER_UPPER} using base path ${BASE_PATH}.');
exception
  when others then
    if sqlcode = -20006 then
      dbms_output.put_line('Schema ${ADMIN_USER_UPPER} is already ORDS enabled.');
    else
      raise;
    end if;
end;
/

exit;
SQL

echo "ORDS enablement complete for ${ADMIN_USER_UPPER}."
