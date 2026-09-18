#!/bin/bash
set -euo pipefail

# Install the DBMS_CLOUD family before the Select AI bootstrap scripts run.
# Oracle AI Database includes these installation scripts, but does not install
# the packages by default on customer-managed databases, including Free.

DB_PASSWORD="${ORACLE_PWD:-${APP_DB_ADMIN_PWD:-}}"
PDB_NAME="${SELECTAI_PDB_NAME:-FREEPDB1}"

if [[ -z "${DB_PASSWORD}" ]]; then
  echo "ORACLE_PWD and APP_DB_ADMIN_PWD are empty; cannot install DBMS_CLOUD."
  exit 1
fi

if [[ ! "${PDB_NAME}" =~ ^[A-Za-z][A-Za-z0-9_$#]*$ ]]; then
  echo "Invalid SELECTAI_PDB_NAME value: ${PDB_NAME}"
  exit 1
fi

PDB_NAME_UPPER="$(echo "${PDB_NAME}" | tr '[:lower:]' '[:upper:]')"

if [[ -z "${ORACLE_HOME:-}" ]]; then
  SQLPLUS_PATH="$(command -v sqlplus || true)"
  if [[ -z "${SQLPLUS_PATH}" ]]; then
    echo "ORACLE_HOME is unset and sqlplus is not on PATH; cannot locate DBMS_CLOUD installation scripts."
    exit 1
  fi
  ORACLE_HOME="$(cd -- "$(dirname -- "${SQLPLUS_PATH}")/.." && pwd)"
fi

ADMIN_DIR="${ORACLE_HOME}/rdbms/admin"
CATCON="${ADMIN_DIR}/catcon.pl"
PERL_BIN="${ORACLE_HOME}/perl/bin/perl"
LOG_DIR="/opt/oracle/cfgtoollogs/dbms_cloud"

for required_path in "${PERL_BIN}" "${CATCON}" \
  "${ADMIN_DIR}/catclouduser.sql" "${ADMIN_DIR}/dbms_cloud_install.sql"; do
  if [[ ! -f "${required_path}" ]]; then
    echo "Required DBMS_CLOUD installation file is missing: ${required_path}"
    exit 1
  fi
done

dbms_cloud_packages_ready() {
  local package_count

  package_count="$(sqlplus -s / as sysdba <<SQL
whenever sqlerror exit sql.sqlcode rollback;
set heading off feedback off pages 0 verify off echo off termout off
alter session set container = ${PDB_NAME_UPPER};
select count(*)
  from dba_objects
 where object_name in ('DBMS_CLOUD', 'DBMS_CLOUD_AI', 'DBMS_CLOUD_AI_AGENT')
   and object_type = 'PACKAGE'
   and status = 'VALID';
exit;
SQL
)" || return 1

  package_count="$(echo "${package_count}" | tr -d '[:space:]')"
  [[ "${package_count}" == "3" ]]
}

if dbms_cloud_packages_ready; then
  echo "DBMS_CLOUD package family is already valid in ${PDB_NAME_UPPER}; skipping installation."
else
  mkdir -p "${LOG_DIR}"

  echo "Installing Oracle DBMS_CLOUD package family with Oracle home ${ORACLE_HOME} ..."
  "${PERL_BIN}" "${CATCON}" \
    -u "sys/${DB_PASSWORD}" \
    -force_pdb_mode 'READ WRITE' \
    -b dbms_cloud_user \
    -d "${ADMIN_DIR}" \
    -l "${LOG_DIR}" \
    catclouduser.sql

  "${PERL_BIN}" "${CATCON}" \
    -u "sys/${DB_PASSWORD}" \
    -force_pdb_mode 'READ WRITE' \
    -b dbms_cloud_install \
    -d "${ADMIN_DIR}" \
    -l "${LOG_DIR}" \
    dbms_cloud_install.sql
fi

sqlplus -s / as sysdba <<SQL
whenever sqlerror exit sql.sqlcode rollback;
set define off
set verify off
set feedback on
set serveroutput on size unlimited

alter session set container = ${PDB_NAME_UPPER};

declare
  l_count number;

  procedure require_valid_package(p_name in varchar2) is
  begin
    select count(*)
      into l_count
      from dba_objects
     where object_name = p_name
       and object_type = 'PACKAGE'
       and status = 'VALID';

    if l_count = 0 then
      raise_application_error(-20062, 'DBMS_CLOUD installation completed, but required package ' || p_name || ' is absent or invalid in ${PDB_NAME_UPPER}.');
    end if;

    dbms_output.put_line('Verified valid package ' || p_name || '.');
  end;
begin
  require_valid_package('DBMS_CLOUD');
  require_valid_package('DBMS_CLOUD_AI');
  require_valid_package('DBMS_CLOUD_AI_AGENT');
end;
/

exit;
SQL

echo "DBMS_CLOUD package family is ready in ${PDB_NAME_UPPER}."
