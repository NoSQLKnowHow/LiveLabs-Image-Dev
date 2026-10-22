#!/usr/bin/env bash
# Opt-in instructor provisioning. Existing workshops remain unchanged by default.
set -euo pipefail
if [[ "${ENABLE_AGENT_MEMORY_ZERO_TO_HERO:-0}" != "1" ]]; then
  echo 'Skipping Agent Memory 26.8 lab (opt in with ENABLE_AGENT_MEMORY_ZERO_TO_HERO=1).'
  exit 0
fi

: "${ZH_DB_PASSWORD:?Set a new password for the dedicated ZH_LAB schema}"
ZH_EMBED_MODEL="${ZH_EMBED_MODEL:-PRISM.ALL_MINILM_L12_V2}"

# Passwords are substituted into SQL, never shell-evaluated. Reject quote/newline
# characters rather than risk SQL substitution. No password is printed.
if [[ ${#ZH_DB_PASSWORD} -lt 14 || "$ZH_DB_PASSWORD" == *\"* || "$ZH_DB_PASSWORD" == *$'\n'* || "$ZH_DB_PASSWORD" == *$'\r'* ]]; then
  echo 'Use a password of at least 14 characters without double quotes or newlines.' >&2
  exit 1
fi
[[ "$ZH_EMBED_MODEL" =~ ^[A-Za-z][A-Za-z0-9_]{0,127}\.[A-Za-z][A-Za-z0-9_]{0,127}$ ]] || exit 1

# Run inside the disposable database container after the original image setup.
# One account is intentional: application scopes are not an authorization layer.
sqlplus -s / as sysdba <<SQL
whenever sqlerror exit failure rollback
whenever oserror exit failure rollback
set echo off verify off feedback off define off
alter session set container = FREEPDB1;

declare
  n number;
begin
  select count(*) into n from dba_users where username = 'ZH_LAB';
  if n <> 0 then
    raise_application_error(-20001, 'ZH_LAB already exists; review rather than overwrite it.');
  end if;
  select count(*) into n from dba_mining_models
    where owner || '.' || model_name = upper('$ZH_EMBED_MODEL');
  if n <> 1 then
    raise_application_error(-20003, 'Import the embedding model before provisioning.');
  end if;
end;
/

create user ZH_LAB identified by "$ZH_DB_PASSWORD" quota 2G on USERS;
grant create session, create table, create view, create sequence,
      create procedure, create trigger, create property graph, create job to ZH_LAB;
grant execute on DBMS_VECTOR to ZH_LAB;
grant select on mining model $ZH_EMBED_MODEL to ZH_LAB;

exit
SQL
echo 'ZH_LAB and embedding-model access ready. Next configure the separate 26.8 kernel.'
