#!/usr/bin/env bash
# Opt-in instructor provisioning. Existing workshops remain unchanged by default.
set -euo pipefail
if [[ "${ENABLE_AGENT_MEMORY_ZERO_TO_HERO:-0}" != "1" ]]; then
  echo 'Skipping Agent Memory 26.8 lab (opt in with ENABLE_AGENT_MEMORY_ZERO_TO_HERO=1).'
  exit 0
fi

: "${ZH_OWNER_PASSWORD:?Set a new password for ZH_OWNER}"
: "${ZH_APP_PASSWORD:?Set a different new password for ZH_APP}"
: "${ZH_IAM_GROUP:?Use the OCI IAM group configured for the two lab end users}"
: "${ZH_RERANK_FILE:?Stage an Oracle-compatible ONNX reranker in DM_DUMP}"

# Passwords are substituted into SQL, never shell-evaluated. Reject quote/newline
# characters rather than risk SQL substitution. No password is printed.
for password in "$ZH_OWNER_PASSWORD" "$ZH_APP_PASSWORD"; do
  if [[ ${#password} -lt 14 || "$password" == *\"* || "$password" == *$'\n'* || "$password" == *$'\r'* ]]; then
    echo 'Use passwords of at least 14 characters without double quotes or newlines.' >&2
    exit 1
  fi
done
if [[ "$ZH_OWNER_PASSWORD" == "$ZH_APP_PASSWORD" ]]; then
  echo 'Owner and runtime accounts must have different passwords.' >&2
  exit 1
fi
[[ "$ZH_IAM_GROUP" =~ ^[A-Za-z][A-Za-z0-9_.:-]{0,127}$ ]] || exit 1
[[ "$ZH_RERANK_FILE" =~ ^[A-Za-z0-9_.-]+\.onnx$ ]] || exit 1
[[ -s "/opt/oracle/dmdump/$ZH_RERANK_FILE" ]] || {
  echo 'Stage the exported reranker in /opt/oracle/dmdump first.' >&2; exit 1;
}

# Run inside the disposable database container. IAM trust/application registration
# is an instructor prerequisite; this script never changes identity providers.
sqlplus -s / as sysdba <<SQL
whenever sqlerror exit failure rollback
whenever oserror exit failure rollback
set echo off verify off feedback off define off
alter session set container = FREEPDB1;

declare
  n number;
begin
  -- Fail before provisioning on an older database without Deep Data Security.
  select count(*) into n from dba_data_roles;
  select count(*) into n from dba_users where username in ('ZH_OWNER', 'ZH_APP');
  if n <> 0 then
    raise_application_error(-20001, 'ZH accounts already exist; review rather than overwrite them.');
  end if;
  select count(*) into n from dba_data_roles
    where upper(mapped_to) = upper('IAM_OAUTH_GROUP=$ZH_IAM_GROUP');
  if n <> 0 then
    raise_application_error(-20002, 'IAM group already mapped; use a dedicated lab group.');
  end if;
end;
/

create user ZH_OWNER identified by "$ZH_OWNER_PASSWORD" quota 2G on USERS;
grant create session, create table, create view, create sequence,
      create procedure, create trigger, create property graph, create job,
      create mining model to ZH_OWNER;
grant execute on DBMS_VECTOR to ZH_OWNER;
grant execute on DBMS_VECTOR_CHAIN to ZH_OWNER;
grant read on directory DM_DUMP to ZH_OWNER;
grant select on mining model PRISM.ALL_MINILM_L12_V2 to ZH_OWNER;

begin
  DBMS_VECTOR.LOAD_ONNX_MODEL(
    directory => 'DM_DUMP', file_name => '$ZH_RERANK_FILE',
    model_name => 'ZH_OWNER.ZH_RERANKER',
    metadata => JSON('{"function":"regression"}'));
end;
/

create user ZH_APP identified by "$ZH_APP_PASSWORD";
grant create session, create end user security context to ZH_APP;
-- Deliberately no ordinary table DML, model privileges, DBA, or owner role.
create role ZH_MODEL_ACCESS;
grant select on mining model PRISM.ALL_MINILM_L12_V2 to ZH_MODEL_ACCESS;
grant select on mining model ZH_OWNER.ZH_RERANKER to ZH_MODEL_ACCESS;
grant execute on DBMS_VECTOR_CHAIN to ZH_MODEL_ACCESS;
create data role ZH_USERS_DATA_ROLE mapped to 'IAM_OAUTH_GROUP=$ZH_IAM_GROUP';
grant ZH_MODEL_ACCESS to ZH_USERS_DATA_ROLE;
exit
SQL
echo 'ZH accounts and database models ready. Next configure the separate 26.8 kernel.'
