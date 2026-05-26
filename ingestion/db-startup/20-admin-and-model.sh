#!/bin/bash
set -euo pipefail

ADMIN_USER="${APP_DB_ADMIN_USER:-ADMIN}"
ADMIN_PWD="${APP_DB_ADMIN_PWD:-${ORACLE_PWD:-}}"
MODEL_NAME="${DB_ONNX_MODEL_NAME:-ALL_MINILM_L12_V2}"
MODEL_FILE="${DB_ONNX_MODEL_FILE:-all_MiniLM_L12_v2.onnx}"
MODEL_URL="${DB_ONNX_MODEL_URL:-https://adwc4pm.objectstorage.us-ashburn-1.oci.customer-oci.com/p/iPX9W0MZeRkwJKWdFmdJCemmN-iKAl_bFvNGYLW7YqIrw4kKsukL24J2q93Beb9S/n/adwc4pm/b/OML-ai-models/o/all_MiniLM_L12_v2.onnx}"

if [[ -z "${ADMIN_PWD}" ]]; then
  echo "APP_DB_ADMIN_PWD and ORACLE_PWD are both empty; cannot provision ${ADMIN_USER}."
  exit 1
fi

if [[ ! "${ADMIN_USER}" =~ ^[A-Za-z][A-Za-z0-9_$#]*$ ]]; then
  echo "Invalid APP_DB_ADMIN_USER value: ${ADMIN_USER}"
  exit 1
fi

ADMIN_USER_UPPER="$(echo "${ADMIN_USER}" | tr '[:lower:]' '[:upper:]')"
ADMIN_PWD_ESCAPED="${ADMIN_PWD//\"/\"\"}"
MODEL_NAME_UPPER="$(echo "${MODEL_NAME}" | tr '[:lower:]' '[:upper:]')"
MODEL_PATH="/opt/oracle/dmdump/${MODEL_FILE}"
APP_USER="$(echo "prism" | tr '[:lower:]' '[:upper:]')"

mkdir -p /opt/oracle/dmdump
if [[ ! -s "${MODEL_PATH}" ]]; then
  echo "Downloading ONNX model to ${MODEL_PATH} ..."
  curl -fL --retry 5 --retry-delay 5 -o "${MODEL_PATH}" "${MODEL_URL}"
else
  echo "ONNX model already present at ${MODEL_PATH}; skipping download."
fi

sqlplus -s / as sysdba <<SQL
whenever sqlerror exit sql.sqlcode;
set define off
set serveroutput on

alter session set container = FREEPDB1;

-- Create the ADMIN user -----
declare
  l_user_count number := 0;
begin
  select count(*)
    into l_user_count
    from dba_users
   where username = '${ADMIN_USER_UPPER}';

  if l_user_count = 0 then
    execute immediate 'create user ${ADMIN_USER_UPPER} identified by "${ADMIN_PWD_ESCAPED}" default tablespace users temporary tablespace temp';
    dbms_output.put_line('Created user ${ADMIN_USER_UPPER}.');
  end if;
end;
/

alter user ${ADMIN_USER_UPPER} identified by "${ADMIN_PWD_ESCAPED}" account unlock;
grant create session to ${ADMIN_USER_UPPER};
grant dba to ${ADMIN_USER_UPPER};
grant unlimited tablespace to ${ADMIN_USER_UPPER};
grant grant any object privilege to ${ADMIN_USER_UPPER};
grant grant any privilege to ${ADMIN_USER_UPPER};
grant grant any role to ${ADMIN_USER_UPPER};
grant execute on sys.dbms_vector to ${ADMIN_USER_UPPER} with grant option;

declare
  l_chain_pkg_count number := 0;
begin
  select count(*)
    into l_chain_pkg_count
    from dba_objects
   where owner = 'CTXSYS'
     and object_name = 'DBMS_VECTOR_CHAIN'
     and object_type = 'PACKAGE';

  if l_chain_pkg_count > 0 then
    execute immediate 'grant execute on ctxsys.dbms_vector_chain to ${ADMIN_USER_UPPER} with grant option';
  else
    dbms_output.put_line('CTXSYS.DBMS_VECTOR_CHAIN not found; skipping grant.');
  end if;
end;
/

--- Create the workshop user ${APP_USER}
declare
  l_user_count number := 0;
begin
  select count(*)
    into l_user_count
    from dba_users
   where username = '${APP_USER}';

  if l_user_count = 0 then
    execute immediate 'create user ${APP_USER} identified by "${ADMIN_PWD_ESCAPED}" default tablespace users temporary tablespace temp';
    dbms_output.put_line('Created user ${APP_USER}.');
  end if;
end;
/

create or replace directory DM_DUMP as '/opt/oracle/dmdump';

ALTER USER ${APP_USER} IDENTIFIED BY "${ADMIN_PWD_ESCAPED}" ACCOUNT UNLOCK;
GRANT CREATE SESSION TO ${APP_USER};
GRANT UNLIMITED TABLESPACE TO ${APP_USER};
GRANT CONNECT, RESOURCE TO ${APP_USER};
GRANT CREATE SESSION TO ${APP_USER};
GRANT CREATE TABLE TO ${APP_USER};
GRANT CREATE VIEW TO ${APP_USER};
GRANT CREATE SEQUENCE TO ${APP_USER};
GRANT CREATE PROCEDURE TO ${APP_USER};
GRANT CREATE TYPE TO ${APP_USER};
ALTER USER ${APP_USER} QUOTA UNLIMITED ON users;

-- JSON and graph
GRANT CREATE PROPERTY GRAPH TO ${APP_USER};

-- Vector and AI
GRANT CREATE MINING MODEL TO ${APP_USER};
GRANT DB_DEVELOPER_ROLE TO ${APP_USER};

-- PL/SQL packages for vector operations
GRANT EXECUTE ON DBMS_VECTOR TO ${APP_USER};
GRANT EXECUTE ON DBMS_VECTOR_CHAIN TO ${APP_USER};
GRANT READ, WRITE ON DIRECTORY DM_DUMP TO ${APP_USER};

-- Allow outbound HTTP from the admin schema for local model providers such as privateai.
-- This is a workshop convenience setting; tighten host scope for production deployments.
declare
begin
  dbms_network_acl_admin.append_host_ace(
    host => '*',
    ace  => xs\$ace_type(
      privilege_list => xs\$name_list('connect', 'resolve'),
      principal_name => '${APP_USER}',
      principal_type => xs_acl.ptype_db
    )
  );
  dbms_output.put_line('Granted wildcard network ACL to ${APP_USER}.');
exception
  when others then
    if sqlcode = -46377 then
      dbms_output.put_line('Wildcard network ACL already exists for ${APP_USER}.');
    else
      raise;
    end if;
end;
/

GRANT READ, WRITE ON DIRECTORY DM_DUMP TO ${APP_USER};

ALTER SESSION SET CURRENT_SCHEMA = ${APP_USER};

declare
  l_model_count number := 0;
begin
  select count(*)
    into l_model_count
    from user_mining_models
   where model_name = '${MODEL_NAME_UPPER}';

  if l_model_count = 0 then
    dbms_vector.load_onnx_model(
      directory => 'DM_DUMP',
      file_name => '${MODEL_FILE}',
      model_name => '${MODEL_NAME_UPPER}',
      metadata => json('{"function":"embedding","embeddingOutput":"embedding","input":{"input":["DATA"]}}')
    );
    dbms_output.put_line('Loaded ONNX model ${MODEL_NAME_UPPER}.');
  else
    dbms_output.put_line('ONNX model ${MODEL_NAME_UPPER} already loaded.');
  end if;
end;
/

exit;
SQL

echo "Provisioning complete: ${ADMIN_USER_UPPER} has DBA privileges and model ${MODEL_NAME_UPPER} is available."
