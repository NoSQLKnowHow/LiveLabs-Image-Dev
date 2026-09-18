#!/bin/bash
set -euo pipefail

# Select AI application developer lab provisioning.
#
# This script runs inside the Oracle Database container after the shared ONNX
# model setup. It creates or resets the dedicated SELECTAI_LAB schema, loads
# deterministic fictional retail data, builds the policy RAG index, provisions
# provider profiles, and creates the Select AI Agent objects used by the
# 30-minute notebook.
#
# OCI Generative AI is provisioned only when all required OCI values and a
# private key are supplied. Provide the key through a mounted file or as base64,
# never as a value printed by this script.

LAB_USER="${SELECTAI_DB_USER:-SELECTAI_LAB}"
LAB_PASSWORD="${SELECTAI_DB_PASSWORD:-${APP_DB_ADMIN_PWD:-${ORACLE_PWD:-Welcome202626ai}}}"
DBCONNECTION="${SELECTAI_DB_CONNECTION:-localhost:1521/freepdb1}"
PDB_NAME="${SELECTAI_PDB_NAME:-FREEPDB1}"

MODEL_NAME="${DB_ONNX_MODEL_NAME:-ALL_MINILM_L12_V2}"
MODEL_OWNER="PRISM"

POLICY_DIR_PATH="${SELECTAI_POLICY_DIR_PATH:-/opt/oracle/select_ai_policies}"
POLICY_DIRECTORY="SELECTAI_POLICY_DIR"
POLICY_VECTOR_INDEX="${SELECTAI_POLICY_VECTOR_INDEX:-SELECTAI_POLICY_VECINDEX}"
POLICY_VECTOR_TABLE="${SELECTAI_POLICY_VECTOR_TABLE:-SELECTAI_POLICY_VECTORS}"
VECTOR_DIMENSION="${SELECTAI_VECTOR_DIMENSION:-384}"

OLLAMA_HOST="${SELECTAI_OLLAMA_HOST:-ollama}"
OLLAMA_PORT="${SELECTAI_OLLAMA_PORT:-11434}"
OLLAMA_MODEL="${SELECTAI_OLLAMA_MODEL:-llama3.2}"
# DBMS_CLOUD_AI appends the OpenAI-compatible API path itself. It requires the
# provider base URL, not Ollama's /v1 path.
OLLAMA_ENDPOINT="${SELECTAI_OLLAMA_ENDPOINT:-http://${OLLAMA_HOST}:${OLLAMA_PORT}}"
OLLAMA_READY_RETRIES="${SELECTAI_OLLAMA_READY_RETRIES:-180}"
OLLAMA_READY_DELAY="${SELECTAI_OLLAMA_READY_DELAY:-5}"

OCI_USER_OCID="${SELECTAI_OCI_USER_OCID:-${USER_OCID:-}}"
OCI_TENANCY_OCID="${SELECTAI_OCI_TENANCY_OCID:-${TENANCY_OCID:-}}"
OCI_FINGERPRINT="${SELECTAI_OCI_FINGERPRINT:-${PEM_KEY_FINGERPRINT:-}}"
OCI_COMPARTMENT_ID="${SELECTAI_OCI_COMPARTMENT_ID:-${COMPARTMENT_OCID:-}}"
OCI_REGION="${SELECTAI_OCI_REGION:-${AI_ENDPOINT_REGION:-${REGION_IDENTIFIER:-}}}"
OCI_MODEL="${SELECTAI_OCI_MODEL:-${OCI_GENAI_CHAT_MODEL:-}}"
OCI_PRIVATE_KEY_FILE="${SELECTAI_OCI_PRIVATE_KEY_FILE:-}"
OCI_PRIVATE_KEY_BASE64="${SELECTAI_OCI_PRIVATE_KEY_BASE64:-}"
OCI_CREDENTIAL_NAME="${SELECTAI_OCI_CREDENTIAL_NAME:-SELECTAI_OCI_CRED}"
REQUIRE_OCI="${SELECTAI_REQUIRE_OCI:-true}"

RUN_PROVIDER_SMOKE_TESTS="${SELECTAI_RUN_PROVIDER_SMOKE_TESTS:-true}"
RUN_AGENT_SMOKE_TESTS="${SELECTAI_RUN_AGENT_SMOKE_TESTS:-false}"

if [[ -z "${LAB_PASSWORD}" ]]; then
  echo "SELECTAI_DB_PASSWORD, APP_DB_ADMIN_PWD, ORACLE_PWD, and the default password fallback are all empty; cannot provision ${LAB_USER}."
  exit 1
fi

for identifier in "${LAB_USER}" "${PDB_NAME}" "${MODEL_NAME}" "${POLICY_VECTOR_INDEX}" "${POLICY_VECTOR_TABLE}" "${OCI_CREDENTIAL_NAME}"; do
  if [[ ! "${identifier}" =~ ^[A-Za-z][A-Za-z0-9_$#]*$ ]]; then
    echo "Invalid Oracle identifier: ${identifier}"
    exit 1
  fi
done

if [[ ! "${VECTOR_DIMENSION}" =~ ^[1-9][0-9]*$ ]]; then
  echo "SELECTAI_VECTOR_DIMENSION must be a positive integer."
  exit 1
fi

if [[ ! "${OLLAMA_PORT}" =~ ^[1-9][0-9]{0,4}$ ]] || (( OLLAMA_PORT > 65535 )); then
  echo "SELECTAI_OLLAMA_PORT must be an integer from 1 through 65535."
  exit 1
fi

if [[ ! "${OLLAMA_READY_RETRIES}" =~ ^[1-9][0-9]*$ ]] || [[ ! "${OLLAMA_READY_DELAY}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Ollama retry and delay settings must be positive integers."
  exit 1
fi

for safe_value in "${OLLAMA_HOST}" "${OLLAMA_MODEL}" "${OLLAMA_ENDPOINT}"; do
  if [[ ! "${safe_value}" =~ ^[A-Za-z0-9._:/-]+$ ]]; then
    echo "An Ollama setting contains unsupported characters."
    exit 1
  fi
done

LAB_USER_UPPER="$(echo "${LAB_USER}" | tr '[:lower:]' '[:upper:]')"
PDB_NAME_UPPER="$(echo "${PDB_NAME}" | tr '[:lower:]' '[:upper:]')"
MODEL_NAME_UPPER="$(echo "${MODEL_NAME}" | tr '[:lower:]' '[:upper:]')"
MODEL_OWNER_UPPER="$(echo "${MODEL_OWNER}" | tr '[:lower:]' '[:upper:]')"
SHARED_MODEL_NAME="${MODEL_OWNER_UPPER}.${MODEL_NAME_UPPER}"
POLICY_VECTOR_INDEX_UPPER="$(echo "${POLICY_VECTOR_INDEX}" | tr '[:lower:]' '[:upper:]')"
POLICY_VECTOR_TABLE_UPPER="$(echo "${POLICY_VECTOR_TABLE}" | tr '[:lower:]' '[:upper:]')"
OCI_CREDENTIAL_NAME_UPPER="$(echo "${OCI_CREDENTIAL_NAME}" | tr '[:lower:]' '[:upper:]')"
LAB_PASSWORD_ESCAPED="${LAB_PASSWORD//\"/\"\"}"

normalize_boolean() {
  local value
  value="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
  case "${value}" in
    true|1|yes) echo "true" ;;
    false|0|no) echo "false" ;;
    *)
      echo "Invalid Boolean value: $1" >&2
      return 1
      ;;
  esac
}

REQUIRE_OCI="$(normalize_boolean "${REQUIRE_OCI}")"
RUN_PROVIDER_SMOKE_TESTS="$(normalize_boolean "${RUN_PROVIDER_SMOKE_TESTS}")"
RUN_AGENT_SMOKE_TESTS="$(normalize_boolean "${RUN_AGENT_SMOKE_TESTS}")"

mkdir -p "${POLICY_DIR_PATH}"
chmod 0755 "${POLICY_DIR_PATH}"

cat >"${POLICY_DIR_PATH}/RETURNS-001.txt" <<'POLICY'
Document ID: RETURNS-001
Title: Standard Merchandise Return Policy
Policy Type: RETURNS
Effective Date: 2026-01-01
Source Label: Fictional Retail Policy Library

Most undamaged merchandise may be returned within 30 calendar days after delivery. The customer must provide the order number. Opened software, personalized items, and gift cards are not returnable. Approved returns receive a refund to the original payment method after the returned item passes inspection.
POLICY

cat >"${POLICY_DIR_PATH}/REFUNDS-001.txt" <<'POLICY'
Document ID: REFUNDS-001
Title: Refund Processing Timeline
Policy Type: REFUNDS
Effective Date: 2026-01-01
Source Label: Fictional Retail Policy Library

After an approved return passes inspection, the refund is submitted within two business days. Banks may require an additional three to five business days to post the credit. Support staff may explain the timeline but may not promise an earlier posting date.
POLICY

cat >"${POLICY_DIR_PATH}/SHIPPING-001.txt" <<'POLICY'
Document ID: SHIPPING-001
Title: Delayed Delivery Response Policy
Policy Type: SHIPPING
Effective Date: 2026-01-01
Source Label: Fictional Retail Policy Library

An order is delayed when its estimated delivery date has passed and delivery is not recorded. Support staff should provide the latest tracking status and may open a carrier trace after two calendar days. A replacement or refund requires the carrier trace or a documented loss event.
POLICY

cat >"${POLICY_DIR_PATH}/WARRANTY-001.txt" <<'POLICY'
Document ID: WARRANTY-001
Title: Limited Product Warranty Policy
Policy Type: WARRANTY
Effective Date: 2026-01-01
Source Label: Fictional Retail Policy Library

The warranty period begins on the delivery date and lasts for the number of months recorded for the product. It covers defects in materials or workmanship under normal use. Accidental damage and ordinary wear are excluded. Support staff should verify the order, delivery date, product warranty period, and reported symptom before starting a warranty claim.
POLICY

echo "========================================================================"
echo "  Select AI Lab: Schema and Privileges"
echo "========================================================================"
echo

sqlplus -s / as sysdba <<SQL
whenever sqlerror exit sql.sqlcode rollback;
set define off
set verify off
set feedback on
set serveroutput on size unlimited

alter session set container = ${PDB_NAME_UPPER};

declare
  l_version   varchar2(100);
  l_container varchar2(128);
  l_major     number;
  l_release   number;
begin
  select version_full
    into l_version
    from v\$instance;

  l_container := sys_context('USERENV', 'CON_NAME');
  dbms_output.put_line('Detected Oracle AI Database release ' || l_version ||
                       ' in container ' || l_container || '.');

  if not regexp_like(l_version, '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$') then
    raise_application_error(-20058, 'Unexpected V\$INSTANCE.VERSION_FULL value: ' || l_version || '.');
  end if;

  l_major  := to_number(regexp_substr(l_version, '[0-9]+', 1, 1));
  l_release := to_number(regexp_substr(l_version, '[0-9]+', 1, 2));

  if l_major < 23 or
     (l_major = 23 and l_release < 26) then
    raise_application_error(-20059, 'Oracle AI Database 23.26.0.0.0 or later is required; found ' || l_version || '.');
  end if;
  dbms_output.put_line('Validated Oracle AI Database release ' || l_version || '.');
exception
  when no_data_found then
    raise_application_error(-20058, 'Unable to read V\$INSTANCE.VERSION_FULL while connected as SYSDBA.');
end;
/

-- The baseline schema and APP_USER-equivalent grants are applied by step 20.
grant create job to ${LAB_USER_UPPER};

create or replace directory ${POLICY_DIRECTORY} as '${POLICY_DIR_PATH}';
grant read, write on directory ${POLICY_DIRECTORY} to ${LAB_USER_UPPER};

declare
  procedure grant_package(p_object_name in varchar2, p_required in boolean) is
    l_owner dba_objects.owner%type;
  begin
    select owner
      into l_owner
      from (
        select owner
          from dba_objects
         where object_name = upper(p_object_name)
           and object_type = 'PACKAGE'
           and status = 'VALID'
         order by case owner when 'SYS' then 1 when 'C##CLOUD\$SERVICE' then 2 else 3 end
      )
     where rownum = 1;

    execute immediate 'grant execute on ' || dbms_assert.schema_name(l_owner) || '.' ||
                      dbms_assert.simple_sql_name(upper(p_object_name)) || ' to ${LAB_USER_UPPER}';
    dbms_output.put_line('Granted ' || l_owner || '.' || upper(p_object_name) || '.');
  exception
    when no_data_found then
      if p_required then
        raise_application_error(-20060, 'Required package ' || upper(p_object_name) || ' is not installed and valid.');
      end if;
      dbms_output.put_line('Optional package ' || upper(p_object_name) || ' is unavailable.');
  end;
begin
  grant_package('DBMS_CLOUD', true);
  grant_package('DBMS_CLOUD_AI', true);
  grant_package('DBMS_CLOUD_AI_AGENT', true);
  grant_package('DBMS_CLOUD_PIPELINE', false);
  grant_package('DBMS_VECTOR', true);
end;
/

declare
  l_count number;
begin
  select count(*) into l_count
    from dba_objects
   where owner = 'CTXSYS'
     and object_name = 'DBMS_VECTOR_CHAIN'
     and object_type = 'PACKAGE'
     and status = 'VALID';
  if l_count > 0 then
    execute immediate 'grant execute on CTXSYS.DBMS_VECTOR_CHAIN to ${LAB_USER_UPPER}';
  end if;

  select count(*) into l_count
    from dba_objects
   where owner = 'CTXSYS'
     and object_name = 'CTX_DDL'
     and object_type = 'PACKAGE'
     and status = 'VALID';
  if l_count > 0 then
    execute immediate 'grant execute on CTXSYS.CTX_DDL to ${LAB_USER_UPPER}';
  end if;
end;
/

declare
  procedure append_resolve_ace(p_host in varchar2) is
  begin
    dbms_network_acl_admin.append_host_ace(
      host => p_host,
      ace  => xs\$ace_type(
                privilege_list => xs\$name_list('resolve'),
                principal_name => '${LAB_USER_UPPER}',
                principal_type => xs_acl.ptype_db));
  exception
    when others then
      if sqlcode != -24243 then raise; end if;
  end;

  procedure append_http_ace(p_host in varchar2, p_port in pls_integer) is
  begin
    dbms_network_acl_admin.append_host_ace(
      host       => p_host,
      lower_port => p_port,
      upper_port => p_port,
      ace        => xs\$ace_type(
                      privilege_list => xs\$name_list('http'),
                      principal_name => '${LAB_USER_UPPER}',
                      principal_type => xs_acl.ptype_db));
  exception
    when others then
      if sqlcode != -24243 then raise; end if;
  end;
begin
  append_resolve_ace('${OLLAMA_HOST}');
  append_http_ace('${OLLAMA_HOST}', ${OLLAMA_PORT});
end;
/

exit;
SQL

echo
echo "========================================================================"
echo "  Select AI Lab: Retail Data and Business Logic"
echo "========================================================================"
echo

sqlplus -s "${LAB_USER}/\"${LAB_PASSWORD_ESCAPED}\"@${DBCONNECTION}" <<SQL
whenever sqlerror exit sql.sqlcode rollback;
set define off
set verify off
set feedback on
set serveroutput on size unlimited

begin dbms_cloud_ai_agent.drop_team('SELECTAI_OCI_TEAM', force => true); end;
/
begin dbms_cloud_ai_agent.drop_team('SELECTAI_OLLAMA_TEAM', force => true); end;
/
begin dbms_cloud_ai_agent.drop_agent('SELECTAI_OCI_AGENT', force => true); end;
/
begin dbms_cloud_ai_agent.drop_agent('SELECTAI_OLLAMA_AGENT', force => true); end;
/
begin dbms_cloud_ai_agent.drop_task('SELECTAI_OCI_TASK', force => true); end;
/
begin dbms_cloud_ai_agent.drop_task('SELECTAI_OLLAMA_TASK', force => true); end;
/
begin dbms_cloud_ai_agent.drop_tool('SELECTAI_OCI_SQL_TOOL', force => true); end;
/
begin dbms_cloud_ai_agent.drop_tool('SELECTAI_OCI_RAG_TOOL', force => true); end;
/
begin dbms_cloud_ai_agent.drop_tool('SELECTAI_OLLAMA_SQL_TOOL', force => true); end;
/
begin dbms_cloud_ai_agent.drop_tool('SELECTAI_OLLAMA_RAG_TOOL', force => true); end;
/
begin dbms_cloud_ai_agent.drop_tool('SELECTAI_ALLOWED_ACTIONS_TOOL', force => true); end;
/

begin
  dbms_cloud_ai.drop_vector_index(
    index_name   => '${POLICY_VECTOR_INDEX_UPPER}',
    include_data => true,
    force        => true);
end;
/

begin dbms_cloud_ai.drop_profile('SELECTAI_OCI_RAG', force => true); end;
/
begin dbms_cloud_ai.drop_profile('SELECTAI_OCI_NL2SQL', force => true); end;
/
begin dbms_cloud_ai.drop_profile('SELECTAI_OLLAMA_RAG', force => true); end;
/
begin dbms_cloud_ai.drop_profile('SELECTAI_OLLAMA_NL2SQL', force => true); end;
/
begin
  dbms_cloud.delete_all_operations('CONVERSATION');
exception
  when others then
    dbms_output.put_line('Conversation reset was not required or is unavailable: ' || sqlerrm);
end;
/

declare
  procedure drop_table_if_exists(p_table_name in varchar2) is
  begin
    execute immediate 'drop table ' || dbms_assert.simple_sql_name(p_table_name) ||
                      ' cascade constraints purge';
  exception
    when others then
      if sqlcode != -942 then raise; end if;
  end;
begin
  drop_table_if_exists('POC_SUPPORT_CASES');
  drop_table_if_exists('SUPPORT_CASES');
  drop_table_if_exists('ORDER_ITEMS');
  drop_table_if_exists('ORDERS');
  drop_table_if_exists('PRODUCTS');
  drop_table_if_exists('CUSTOMERS');
  drop_table_if_exists('POLICY_DOCUMENTS');
  drop_table_if_exists('SELECTAI_BUILD_LOG');
end;
/

create table customers (
  customer_id  number generated by default on null as identity,
  full_name    varchar2(100) not null,
  email        varchar2(160) not null,
  region       varchar2(20) not null,
  loyalty_tier varchar2(12) default 'STANDARD' not null,
  constraint customers_pk primary key (customer_id),
  constraint customers_email_uk unique (email),
  constraint customers_region_ck check (region in ('NORTHEAST','SOUTHEAST','MIDWEST','SOUTHWEST','WEST')),
  constraint customers_tier_ck check (loyalty_tier in ('STANDARD','SILVER','GOLD'))
);

create table products (
  product_id       number generated by default on null as identity,
  product_name     varchar2(120) not null,
  category         varchar2(40) not null,
  unit_price       number(10,2) not null,
  warranty_months  number(3) default 12 not null,
  returnable_flag  char(1) default 'Y' not null,
  constraint products_pk primary key (product_id),
  constraint products_price_ck check (unit_price >= 0),
  constraint products_warranty_ck check (warranty_months between 0 and 120),
  constraint products_returnable_ck check (returnable_flag in ('Y','N'))
);

create table orders (
  order_id                number generated by default on null as identity,
  customer_id             number not null,
  order_date              date not null,
  status                  varchar2(20) not null,
  estimated_delivery_date date,
  shipped_date            date,
  delivered_date          date,
  total_amount            number(12,2) not null,
  constraint orders_pk primary key (order_id),
  constraint orders_customer_fk foreign key (customer_id) references customers(customer_id),
  constraint orders_status_ck check (status in ('PROCESSING','SHIPPED','DELAYED','DELIVERED','CANCELLED','REFUNDED')),
  constraint orders_total_ck check (total_amount >= 0),
  constraint orders_dates_ck check (delivered_date is null or shipped_date is null or delivered_date >= shipped_date)
);

create table order_items (
  order_id    number not null,
  line_number number(4) not null,
  product_id  number not null,
  quantity    number(6) not null,
  unit_price  number(10,2) not null,
  constraint order_items_pk primary key (order_id, line_number),
  constraint order_items_order_fk foreign key (order_id) references orders(order_id),
  constraint order_items_product_fk foreign key (product_id) references products(product_id),
  constraint order_items_quantity_ck check (quantity > 0),
  constraint order_items_price_ck check (unit_price >= 0)
);

create table support_cases (
  case_id      number generated by default on null as identity,
  customer_id  number not null,
  order_id     number,
  opened_at    timestamp default systimestamp not null,
  category     varchar2(30) not null,
  status       varchar2(20) not null,
  priority     varchar2(10) default 'MEDIUM' not null,
  summary      varchar2(500) not null,
  constraint support_cases_pk primary key (case_id),
  constraint support_cases_customer_fk foreign key (customer_id) references customers(customer_id),
  constraint support_cases_order_fk foreign key (order_id) references orders(order_id),
  constraint support_cases_category_ck check (category in ('RETURN','REFUND','SHIPPING','WARRANTY','PRODUCT','OTHER')),
  constraint support_cases_status_ck check (status in ('NEW','IN_PROGRESS','WAITING_CUSTOMER','RESOLVED','CLOSED')),
  constraint support_cases_priority_ck check (priority in ('LOW','MEDIUM','HIGH'))
);

create table poc_support_cases (
  case_id      number generated by default on null as identity,
  customer_id  number not null,
  order_id     number,
  opened_at    timestamp default systimestamp not null,
  category     varchar2(30) not null,
  status       varchar2(20) not null,
  priority     varchar2(10) default 'MEDIUM' not null,
  summary      varchar2(500) not null,
  constraint poc_support_cases_pk primary key (case_id),
  constraint poc_cases_customer_fk foreign key (customer_id) references customers(customer_id),
  constraint poc_cases_order_fk foreign key (order_id) references orders(order_id),
  constraint poc_cases_category_ck check (category in ('RETURN','REFUND','SHIPPING','WARRANTY','PRODUCT','OTHER')),
  constraint poc_cases_status_ck check (status in ('NEW','IN_PROGRESS','WAITING_CUSTOMER','RESOLVED','CLOSED')),
  constraint poc_cases_priority_ck check (priority in ('LOW','MEDIUM','HIGH'))
);

create table policy_documents (
  policy_id      varchar2(30) not null,
  title          varchar2(160) not null,
  policy_type    varchar2(30) not null,
  effective_date date not null,
  source_label   varchar2(100) not null,
  policy_text    clob not null,
  constraint policy_documents_pk primary key (policy_id),
  constraint policy_documents_type_ck check (policy_type in ('RETURNS','REFUNDS','SHIPPING','WARRANTY'))
);

create table selectai_build_log (
  logged_at timestamp default systimestamp not null,
  step_name varchar2(80) not null,
  status    varchar2(12) not null,
  detail    varchar2(4000),
  constraint selectai_build_log_status_ck check (status in ('SUCCESS','WARNING','FAILURE'))
);

comment on table customers is 'Fictional retail customers used by the Select AI application developer lab.';
comment on column customers.region is 'Customer service region: NORTHEAST, SOUTHEAST, MIDWEST, SOUTHWEST, or WEST.';
comment on column customers.loyalty_tier is 'Customer loyalty tier: STANDARD, SILVER, or GOLD.';
comment on table products is 'Fictional catalog products with price, return eligibility, and warranty duration.';
comment on column products.warranty_months is 'Number of warranty months beginning on the order delivery date.';
comment on column products.returnable_flag is 'Y when the product category is eligible for the standard return policy.';
comment on table orders is 'Fictional customer orders and their delivery lifecycle.';
comment on column orders.status is 'Order lifecycle status. DELAYED means the estimated delivery date passed without delivery.';
comment on column orders.delivered_date is 'Actual delivery date. The standard return window begins on this date.';
comment on table order_items is 'Products and quantities belonging to an order. Join to ORDERS with ORDER_ID and PRODUCTS with PRODUCT_ID.';
comment on table support_cases is 'Existing fictional support activity. An open case has status NEW, IN_PROGRESS, or WAITING_CUSTOMER.';
comment on column support_cases.status is 'NEW, IN_PROGRESS, and WAITING_CUSTOMER are open statuses. RESOLVED and CLOSED are not open.';
comment on table poc_support_cases is 'Disposable target for participant-generated fictional prototype data.';
comment on table policy_documents is 'Relational copy of the fictional policy corpus used to verify document identifiers and policy facts.';

insert into customers (customer_id, full_name, email, region, loyalty_tier) values (101, 'Avery Morgan', 'avery.morgan@example.invalid', 'NORTHEAST', 'GOLD');
insert into customers (customer_id, full_name, email, region, loyalty_tier) values (102, 'Jordan Lee', 'jordan.lee@example.invalid', 'WEST', 'SILVER');
insert into customers (customer_id, full_name, email, region, loyalty_tier) values (103, 'Casey Patel', 'casey.patel@example.invalid', 'SOUTHEAST', 'STANDARD');
insert into customers (customer_id, full_name, email, region, loyalty_tier) values (104, 'Riley Chen', 'riley.chen@example.invalid', 'MIDWEST', 'GOLD');
insert into customers (customer_id, full_name, email, region, loyalty_tier) values (105, 'Taylor Brooks', 'taylor.brooks@example.invalid', 'SOUTHWEST', 'SILVER');
insert into customers (customer_id, full_name, email, region, loyalty_tier) values (106, 'Morgan Diaz', 'morgan.diaz@example.invalid', 'WEST', 'STANDARD');

insert into products (product_id, product_name, category, unit_price, warranty_months, returnable_flag) values (501, 'Orion Wireless Headphones', 'AUDIO', 149.00, 24, 'Y');
insert into products (product_id, product_name, category, unit_price, warranty_months, returnable_flag) values (502, 'Nova Smart Lamp', 'HOME', 79.00, 12, 'Y');
insert into products (product_id, product_name, category, unit_price, warranty_months, returnable_flag) values (503, 'Atlas Travel Backpack', 'TRAVEL', 119.00, 12, 'Y');
insert into products (product_id, product_name, category, unit_price, warranty_months, returnable_flag) values (504, 'Kepler Mechanical Keyboard', 'COMPUTING', 129.00, 24, 'Y');
insert into products (product_id, product_name, category, unit_price, warranty_months, returnable_flag) values (505, 'Digital Gift Card', 'GIFT_CARD', 50.00, 0, 'N');
insert into products (product_id, product_name, category, unit_price, warranty_months, returnable_flag) values (506, 'Solstice Fitness Tracker', 'WEARABLE', 199.00, 18, 'Y');

insert into orders (order_id, customer_id, order_date, status, estimated_delivery_date, shipped_date, delivered_date, total_amount)
values (1042, 101, trunc(sysdate)-14, 'DELIVERED', trunc(sysdate)-11, trunc(sysdate)-12, trunc(sysdate)-10, 149.00);
insert into orders (order_id, customer_id, order_date, status, estimated_delivery_date, shipped_date, delivered_date, total_amount)
values (1030, 102, trunc(sysdate)-52, 'DELIVERED', trunc(sysdate)-47, trunc(sysdate)-49, trunc(sysdate)-45, 79.00);
insert into orders (order_id, customer_id, order_date, status, estimated_delivery_date, shipped_date, delivered_date, total_amount)
values (1043, 103, trunc(sysdate)-8, 'DELAYED', trunc(sysdate)-2, trunc(sysdate)-7, null, 119.00);
insert into orders (order_id, customer_id, order_date, status, estimated_delivery_date, shipped_date, delivered_date, total_amount)
values (1044, 104, trunc(sysdate)-160, 'DELIVERED', trunc(sysdate)-155, trunc(sysdate)-158, trunc(sysdate)-154, 129.00);
insert into orders (order_id, customer_id, order_date, status, estimated_delivery_date, shipped_date, delivered_date, total_amount)
values (1045, 105, trunc(sysdate)-1, 'PROCESSING', trunc(sysdate)+4, null, null, 50.00);
insert into orders (order_id, customer_id, order_date, status, estimated_delivery_date, shipped_date, delivered_date, total_amount)
values (1046, 106, trunc(sysdate)-5, 'SHIPPED', trunc(sysdate)+1, trunc(sysdate)-3, null, 199.00);

insert into order_items values (1042, 1, 501, 1, 149.00);
insert into order_items values (1030, 1, 502, 1, 79.00);
insert into order_items values (1043, 1, 503, 1, 119.00);
insert into order_items values (1044, 1, 504, 1, 129.00);
insert into order_items values (1045, 1, 505, 1, 50.00);
insert into order_items values (1046, 1, 506, 1, 199.00);

insert into support_cases (case_id, customer_id, order_id, opened_at, category, status, priority, summary)
values (7001, 101, 1042, systimestamp - interval '1' day, 'RETURN', 'NEW', 'MEDIUM', 'Customer asks whether delivered headphones are still returnable.');
insert into support_cases (case_id, customer_id, order_id, opened_at, category, status, priority, summary)
values (7002, 103, 1043, systimestamp - interval '2' day, 'SHIPPING', 'IN_PROGRESS', 'HIGH', 'Delivery estimate passed and carrier tracking has not changed.');
insert into support_cases (case_id, customer_id, order_id, opened_at, category, status, priority, summary)
values (7003, 104, 1044, systimestamp - interval '5' day, 'WARRANTY', 'WAITING_CUSTOMER', 'MEDIUM', 'Keyboard intermittently disconnects during normal use.');
insert into support_cases (case_id, customer_id, order_id, opened_at, category, status, priority, summary)
values (7004, 102, 1030, systimestamp - interval '20' day, 'RETURN', 'CLOSED', 'LOW', 'Return request was outside the standard return window.');

insert into policy_documents values ('RETURNS-001', 'Standard Merchandise Return Policy', 'RETURNS', date '2026-01-01', 'Fictional Retail Policy Library',
  'Most undamaged merchandise may be returned within 30 calendar days after delivery. The customer must provide the order number. Opened software, personalized items, and gift cards are not returnable.');
insert into policy_documents values ('REFUNDS-001', 'Refund Processing Timeline', 'REFUNDS', date '2026-01-01', 'Fictional Retail Policy Library',
  'After an approved return passes inspection, the refund is submitted within two business days. Banks may require an additional three to five business days to post the credit.');
insert into policy_documents values ('SHIPPING-001', 'Delayed Delivery Response Policy', 'SHIPPING', date '2026-01-01', 'Fictional Retail Policy Library',
  'An order is delayed when its estimated delivery date has passed and delivery is not recorded. Support may open a carrier trace after two calendar days.');
insert into policy_documents values ('WARRANTY-001', 'Limited Product Warranty Policy', 'WARRANTY', date '2026-01-01', 'Fictional Retail Policy Library',
  'The warranty begins on the delivery date and lasts for the number of months recorded for the product. Defects in materials or workmanship under normal use are covered.');

create or replace function get_allowed_support_actions(p_order_id in number)
  return clob
  authid definer
is
  l_status          orders.status%type;
  l_delivered_date  orders.delivered_date%type;
  l_returnable      products.returnable_flag%type;
  l_warranty_months products.warranty_months%type;
  l_open_cases      number;
  l_actions         varchar2(1000);
  l_response        json_object_t := json_object_t();
begin
  select o.status, o.delivered_date,
         min(p.returnable_flag), max(p.warranty_months)
    into l_status, l_delivered_date, l_returnable, l_warranty_months
    from orders o
    join order_items oi on oi.order_id = o.order_id
    join products p on p.product_id = oi.product_id
   where o.order_id = p_order_id
   group by o.status, o.delivered_date;

  select count(*)
    into l_open_cases
    from support_cases
   where order_id = p_order_id
     and status in ('NEW','IN_PROGRESS','WAITING_CUSTOMER');

  if l_status = 'DELAYED' then
    l_actions := 'PROVIDE_TRACKING_STATUS, OPEN_CARRIER_TRACE_AFTER_TWO_DAYS';
  elsif l_status = 'SHIPPED' then
    l_actions := 'PROVIDE_TRACKING_STATUS';
  elsif l_status = 'DELIVERED' and l_returnable = 'Y' and trunc(sysdate) - trunc(l_delivered_date) <= 30 then
    l_actions := 'VERIFY_ITEM_CONDITION, START_RETURN_REVIEW';
  elsif l_status = 'DELIVERED' and l_warranty_months > 0 and
        add_months(trunc(l_delivered_date), l_warranty_months) >= trunc(sysdate) then
    l_actions := 'VERIFY_REPORTED_SYMPTOM, START_WARRANTY_REVIEW';
  elsif l_status in ('CANCELLED','REFUNDED') then
    l_actions := 'REVIEW_ORDER_HISTORY_ONLY';
  else
    l_actions := 'ESCALATE_FOR_POLICY_REVIEW';
  end if;

  if l_open_cases > 0 then
    l_actions := l_actions || ', LINK_EXISTING_OPEN_CASE';
  end if;

  l_response.put('order_id', p_order_id);
  l_response.put('order_status', l_status);
  l_response.put('permitted_actions', l_actions);
  l_response.put('open_case_count', l_open_cases);
  return l_response.to_clob;
exception
  when no_data_found then
    l_response.put('order_id', p_order_id);
    l_response.put('permitted_actions', 'REVIEW_ORDER_NOT_FOUND');
    return l_response.to_clob;
end;
/

declare
  l_error_count pls_integer;
begin
  select count(*)
    into l_error_count
    from user_errors
   where name = 'GET_ALLOWED_SUPPORT_ACTIONS'
     and type = 'FUNCTION';

  if l_error_count > 0 then
    dbms_output.put_line('Compilation errors for GET_ALLOWED_SUPPORT_ACTIONS:');
    for r in (
      select line, position, text
        from user_errors
       where name = 'GET_ALLOWED_SUPPORT_ACTIONS'
         and type = 'FUNCTION'
       order by sequence
    ) loop
      dbms_output.put_line('  line ' || r.line || ', column ' || r.position || ': ' || r.text);
    end loop;
    raise_application_error(-20063, 'GET_ALLOWED_SUPPORT_ACTIONS is invalid. Review the compilation errors above.');
  end if;
end;
/

declare
  l_result clob;
begin
  l_result := get_allowed_support_actions(1042);
  if dbms_lob.instr(l_result, 'START_RETURN_REVIEW') = 0 then
    raise_application_error(-20061, 'GET_ALLOWED_SUPPORT_ACTIONS did not return the expected action for order 1042.');
  end if;
  dbms_output.put_line('Validated GET_ALLOWED_SUPPORT_ACTIONS for order 1042.');
end;
/

exit;
SQL

echo
echo "========================================================================"
echo "  Select AI Lab: Policy Vector Index"
echo "========================================================================"
echo

sqlplus -s "${LAB_USER}/\"${LAB_PASSWORD_ESCAPED}\"@${DBCONNECTION}" <<SQL
whenever sqlerror exit sql.sqlcode rollback;
set define off
set verify off
set feedback on
set serveroutput on size unlimited

begin
  -- CREATE_VECTOR_INDEX is a Select AI pipeline. It needs the complete
  -- provider profile used for RAG, even though this profile uses the shared
  -- in-database ONNX model for its embeddings.
  begin
    dbms_cloud.drop_credential('SELECTAI_OLLAMA_CRED');
  exception
    when others then null;
  end;

  dbms_cloud.create_credential(
    credential_name => 'SELECTAI_OLLAMA_CRED',
    username        => 'OLLAMA',
    password        => 'local-private-endpoint');

  dbms_cloud_ai.create_profile(
    profile_name => 'SELECTAI_OLLAMA_RAG',
    attributes   => '{"provider":"openai","credential_name":"SELECTAI_OLLAMA_CRED","provider_endpoint":"${OLLAMA_ENDPOINT}","model":"${OLLAMA_MODEL}","conversation":"true","embedding_model":"database: ${SHARED_MODEL_NAME}","vector_index_name":"${POLICY_VECTOR_INDEX_UPPER}","enable_sources":"true","temperature":0,"max_tokens":1200}',
    status       => 'ENABLED',
    description  => 'Ollama RAG profile using the shared in-database ONNX embedding model.');
end;
/

begin
  dbms_output.put_line('Creating policy vector index with SELECTAI_OLLAMA_RAG and shared model ${SHARED_MODEL_NAME}.');
  dbms_cloud_ai.create_vector_index(
    index_name          => '${POLICY_VECTOR_INDEX_UPPER}',
    attributes          => '{"vector_db_provider":"oracle","vector_table_name":"${POLICY_VECTOR_TABLE_UPPER}","profile_name":"SELECTAI_OLLAMA_RAG","location":"${POLICY_DIRECTORY}:*.txt","object_storage_credential_name":"SELECTAI_OLLAMA_CRED","vector_dimension":${VECTOR_DIMENSION},"vector_distance_metric":"cosine","chunk_size":512,"chunk_overlap":64}',
    status              => 'ENABLED',
    description         => 'Fictional retail returns, refunds, shipping, and warranty policy corpus.',
    wait_for_completion => true);
  dbms_output.put_line('Policy vector index creation completed.');
end;
/

exit;
SQL

echo
echo "========================================================================"
echo "  Select AI Lab: Ollama Provider Bundle"
echo "========================================================================"
echo

sqlplus -s "${LAB_USER}/\"${LAB_PASSWORD_ESCAPED}\"@${DBCONNECTION}" <<SQL
whenever sqlerror exit sql.sqlcode rollback;
set define off
set verify off
set feedback on
set serveroutput on size unlimited

begin
  dbms_cloud_ai.create_profile(
    profile_name => 'SELECTAI_OLLAMA_NL2SQL',
    attributes   => '{"provider":"openai","credential_name":"SELECTAI_OLLAMA_CRED","provider_endpoint":"${OLLAMA_ENDPOINT}","model":"${OLLAMA_MODEL}","conversation":"true","comments":"true","annotations":"true","constraints":"true","enforce_object_list":"true","object_list_mode":"all","temperature":0,"max_tokens":1200,"object_list":[{"owner":"${LAB_USER_UPPER}","name":"CUSTOMERS"},{"owner":"${LAB_USER_UPPER}","name":"PRODUCTS"},{"owner":"${LAB_USER_UPPER}","name":"ORDERS"},{"owner":"${LAB_USER_UPPER}","name":"ORDER_ITEMS"},{"owner":"${LAB_USER_UPPER}","name":"SUPPORT_CASES"},{"owner":"${LAB_USER_UPPER}","name":"POC_SUPPORT_CASES"}]}',
    status       => 'ENABLED',
    description  => 'Ollama NL2SQL profile for the Select AI application developer lab.');

end;
/

begin
  dbms_cloud_ai_agent.create_tool(
    tool_name   => 'SELECTAI_OLLAMA_SQL_TOOL',
    attributes  => '{"tool_type":"SQL","tool_params":{"profile_name":"SELECTAI_OLLAMA_NL2SQL"}}',
    status      => 'ENABLED',
    description => 'Queries structured retail facts through the scoped Ollama NL2SQL profile.');

  dbms_cloud_ai_agent.create_tool(
    tool_name   => 'SELECTAI_OLLAMA_RAG_TOOL',
    attributes  => '{"tool_type":"RAG","tool_params":{"profile_name":"SELECTAI_OLLAMA_RAG"}}',
    status      => 'ENABLED',
    description => 'Retrieves grounded policy guidance through the Ollama RAG profile.');

  dbms_cloud_ai_agent.create_task(
    task_name   => 'SELECTAI_OLLAMA_TASK',
    attributes  => '{"instruction":"Review the user request. Use the SQL tool for order, customer, product, and support-case facts. Use the RAG tool for policy guidance. Clearly separate database facts from policy guidance and include policy source identifiers when available. Do not claim that an action was performed.","tools":["SELECTAI_OLLAMA_SQL_TOOL","SELECTAI_OLLAMA_RAG_TOOL"]}',
    status      => 'ENABLED',
    description => 'Combines structured retail facts and policy guidance without performing DML.');

  dbms_cloud_ai_agent.create_agent(
    agent_name  => 'SELECTAI_OLLAMA_AGENT',
    attributes  => '{"profile_name":"SELECTAI_OLLAMA_NL2SQL","role":"You are a careful retail support application assistant. Distinguish verified order facts from policy guidance and recommend only permitted next steps."}',
    status      => 'ENABLED',
    description => 'Ollama-backed agent for the Select AI order-support capstone.');

  dbms_cloud_ai_agent.create_team(
    team_name   => 'SELECTAI_OLLAMA_TEAM',
    attributes  => '{"agents":[{"name":"SELECTAI_OLLAMA_AGENT","task":"SELECTAI_OLLAMA_TASK"}],"process":"sequential"}',
    status      => 'ENABLED',
    description => 'Ollama SQL-plus-RAG team for the Select AI application developer lab.');
end;
/

begin
  dbms_cloud_ai_agent.create_tool(
    tool_name   => 'SELECTAI_ALLOWED_ACTIONS_TOOL',
    attributes  => '{"instruction":"Return deterministic permitted support actions for the supplied order ID. This tool is read-only and does not perform an action.","function":"${LAB_USER_UPPER}.GET_ALLOWED_SUPPORT_ACTIONS","tool_inputs":[{"name":"P_ORDER_ID","description":"Numeric order identifier to review."}]}',
    status      => 'ENABLED',
    description => 'Candidate read-only custom tool. It is intentionally excluded from the timed mandatory task.');
end;
/

exit;
SQL

OCI_ENABLED="false"
if [[ -z "${OCI_PRIVATE_KEY_BASE64}" && -n "${OCI_PRIVATE_KEY_FILE}" ]]; then
  if [[ ! -r "${OCI_PRIVATE_KEY_FILE}" ]]; then
    echo "SELECTAI_OCI_PRIVATE_KEY_FILE is not readable inside the database container."
    exit 1
  fi
  if grep -Fq '\n' "${OCI_PRIVATE_KEY_FILE}"; then
    OCI_PRIVATE_KEY_BASE64="$(
      printf '%b' "$(tr -d '\r' <"${OCI_PRIVATE_KEY_FILE}")" |
        awk '/-----BEGIN .*PRIVATE KEY-----/{copy=1} copy{print} /-----END .*PRIVATE KEY-----/{exit}' |
        base64 | tr -d '\r\n'
    )"
  else
    OCI_PRIVATE_KEY_BASE64="$(
      awk '/-----BEGIN .*PRIVATE KEY-----/{copy=1} copy{print} /-----END .*PRIVATE KEY-----/{exit}' "${OCI_PRIVATE_KEY_FILE}" |
        base64 | tr -d '\r\n'
    )"
  fi
fi

if [[ -n "${OCI_USER_OCID}" && -n "${OCI_TENANCY_OCID}" && -n "${OCI_FINGERPRINT}" &&
      -n "${OCI_COMPARTMENT_ID}" && -n "${OCI_REGION}" && -n "${OCI_MODEL}" &&
      -n "${OCI_PRIVATE_KEY_BASE64}" ]]; then
  OCI_ENABLED="true"
fi

if [[ "${REQUIRE_OCI}" == "true" && "${OCI_ENABLED}" != "true" ]]; then
  echo "OCI provisioning is required but its identifiers, model, or private key are incomplete."
  echo "Supply SELECTAI_OCI_USER_OCID, SELECTAI_OCI_TENANCY_OCID, SELECTAI_OCI_FINGERPRINT, SELECTAI_OCI_COMPARTMENT_ID, SELECTAI_OCI_REGION, SELECTAI_OCI_MODEL, and either SELECTAI_OCI_PRIVATE_KEY_FILE or SELECTAI_OCI_PRIVATE_KEY_BASE64."
  exit 1
fi

if [[ "${OCI_ENABLED}" == "true" ]]; then
  for safe_value in "${OCI_USER_OCID}" "${OCI_TENANCY_OCID}" "${OCI_FINGERPRINT}" "${OCI_COMPARTMENT_ID}" "${OCI_REGION}" "${OCI_MODEL}"; do
    if [[ ! "${safe_value}" =~ ^[A-Za-z0-9._:/-]+$ ]]; then
      echo "An OCI setting contains unsupported characters."
      exit 1
    fi
  done
  if [[ ! "${OCI_PRIVATE_KEY_BASE64}" =~ ^[A-Za-z0-9+/=]+$ ]]; then
    echo "SELECTAI_OCI_PRIVATE_KEY_BASE64 is not valid single-line base64."
    exit 1
  fi

  OCI_INFERENCE_HOST="inference.generativeai.${OCI_REGION}.oci.oraclecloud.com"

  echo
  echo "========================================================================"
  echo "  Select AI Lab: OCI Generative AI Provider Bundle"
  echo "========================================================================"
  echo

  sqlplus -s / as sysdba <<SQL
whenever sqlerror exit sql.sqlcode rollback;
set define off
set verify off
set feedback on
set serveroutput on size unlimited

alter session set container = ${PDB_NAME_UPPER};

declare
  procedure append_resolve_ace(p_host in varchar2) is
  begin
    dbms_network_acl_admin.append_host_ace(
      host => p_host,
      ace  => xs\$ace_type(
                privilege_list => xs\$name_list('resolve'),
                principal_name => '${LAB_USER_UPPER}',
                principal_type => xs_acl.ptype_db));
  exception
    when others then
      if sqlcode != -24243 then raise; end if;
  end;

  procedure append_http_ace(p_host in varchar2) is
  begin
    dbms_network_acl_admin.append_host_ace(
      host       => p_host,
      lower_port => 443,
      upper_port => 443,
      ace        => xs\$ace_type(
                      privilege_list => xs\$name_list('http'),
                      principal_name => '${LAB_USER_UPPER}',
                      principal_type => xs_acl.ptype_db));
  exception
    when others then
      if sqlcode != -24243 then raise; end if;
  end;
begin
  append_resolve_ace('${OCI_INFERENCE_HOST}');
  append_http_ace('${OCI_INFERENCE_HOST}');
end;
/

exit;
SQL

  sqlplus -s "${LAB_USER}/\"${LAB_PASSWORD_ESCAPED}\"@${DBCONNECTION}" <<SQL
whenever sqlerror exit sql.sqlcode rollback;
set define off
set verify off
set feedback on
set serveroutput on size unlimited

declare
  l_private_key varchar2(32767);
begin
  l_private_key := utl_raw.cast_to_varchar2(
                     utl_encode.base64_decode(
                       utl_raw.cast_to_raw('${OCI_PRIVATE_KEY_BASE64}')));

  begin
    dbms_cloud.drop_credential('${OCI_CREDENTIAL_NAME_UPPER}');
  exception
    when others then null;
  end;

  dbms_cloud.create_credential(
    credential_name => '${OCI_CREDENTIAL_NAME_UPPER}',
    user_ocid       => '${OCI_USER_OCID}',
    tenancy_ocid    => '${OCI_TENANCY_OCID}',
    private_key     => l_private_key,
    fingerprint     => '${OCI_FINGERPRINT}');

  dbms_cloud_ai.create_profile(
    profile_name => 'SELECTAI_OCI_NL2SQL',
    attributes   => '{"provider":"oci","credential_name":"${OCI_CREDENTIAL_NAME_UPPER}","region":"${OCI_REGION}","oci_compartment_id":"${OCI_COMPARTMENT_ID}","model":"${OCI_MODEL}","conversation":"true","comments":"true","annotations":"true","constraints":"true","enforce_object_list":"true","object_list_mode":"all","temperature":0,"max_tokens":1200,"object_list":[{"owner":"${LAB_USER_UPPER}","name":"CUSTOMERS"},{"owner":"${LAB_USER_UPPER}","name":"PRODUCTS"},{"owner":"${LAB_USER_UPPER}","name":"ORDERS"},{"owner":"${LAB_USER_UPPER}","name":"ORDER_ITEMS"},{"owner":"${LAB_USER_UPPER}","name":"SUPPORT_CASES"},{"owner":"${LAB_USER_UPPER}","name":"POC_SUPPORT_CASES"}]}',
    status       => 'ENABLED',
    description  => 'OCI Generative AI NL2SQL profile for the Select AI application developer lab.');

  dbms_cloud_ai.create_profile(
    profile_name => 'SELECTAI_OCI_RAG',
    attributes   => '{"provider":"oci","credential_name":"${OCI_CREDENTIAL_NAME_UPPER}","region":"${OCI_REGION}","oci_compartment_id":"${OCI_COMPARTMENT_ID}","model":"${OCI_MODEL}","conversation":"true","embedding_model":"database: ${SHARED_MODEL_NAME}","vector_index_name":"${POLICY_VECTOR_INDEX_UPPER}","enable_sources":"true","temperature":0,"max_tokens":1200}',
    status       => 'ENABLED',
    description  => 'OCI Generative AI RAG profile for the fictional retail policy corpus.');
end;
/

begin
  dbms_cloud_ai_agent.create_tool(
    tool_name   => 'SELECTAI_OCI_SQL_TOOL',
    attributes  => '{"tool_type":"SQL","tool_params":{"profile_name":"SELECTAI_OCI_NL2SQL"}}',
    status      => 'ENABLED',
    description => 'Queries structured retail facts through the scoped OCI NL2SQL profile.');

  dbms_cloud_ai_agent.create_tool(
    tool_name   => 'SELECTAI_OCI_RAG_TOOL',
    attributes  => '{"tool_type":"RAG","tool_params":{"profile_name":"SELECTAI_OCI_RAG"}}',
    status      => 'ENABLED',
    description => 'Retrieves grounded policy guidance through the OCI RAG profile.');

  dbms_cloud_ai_agent.create_task(
    task_name   => 'SELECTAI_OCI_TASK',
    attributes  => '{"instruction":"Review the user request. Use the SQL tool for order, customer, product, and support-case facts. Use the RAG tool for policy guidance. Clearly separate database facts from policy guidance and include policy source identifiers when available. Do not claim that an action was performed.","tools":["SELECTAI_OCI_SQL_TOOL","SELECTAI_OCI_RAG_TOOL"]}',
    status      => 'ENABLED',
    description => 'Combines structured retail facts and policy guidance without performing DML.');

  dbms_cloud_ai_agent.create_agent(
    agent_name  => 'SELECTAI_OCI_AGENT',
    attributes  => '{"profile_name":"SELECTAI_OCI_NL2SQL","role":"You are a careful retail support application assistant. Distinguish verified order facts from policy guidance and recommend only permitted next steps."}',
    status      => 'ENABLED',
    description => 'OCI-backed agent for the Select AI order-support capstone.');

  dbms_cloud_ai_agent.create_team(
    team_name   => 'SELECTAI_OCI_TEAM',
    attributes  => '{"agents":[{"name":"SELECTAI_OCI_AGENT","task":"SELECTAI_OCI_TASK"}],"process":"sequential"}',
    status      => 'ENABLED',
    description => 'OCI SQL-plus-RAG team for the Select AI application developer lab.');
end;
/

exit;
SQL
else
  echo
  echo "OCI bundle skipped because its credential inputs are incomplete."
  echo "Ollama database objects are provisioned, but the full two-provider notebook preflight remains incomplete."
fi

echo
echo "========================================================================"
echo "  Select AI Lab: Ollama Readiness"
echo "========================================================================"
echo

OLLAMA_API_BASE="http://${OLLAMA_HOST}:${OLLAMA_PORT}"
OLLAMA_READY="false"
for ((attempt = 1; attempt <= OLLAMA_READY_RETRIES; attempt++)); do
  tags_json="$(curl -fsS --max-time 10 "${OLLAMA_API_BASE}/api/tags" 2>/dev/null || true)"
  if [[ -n "${tags_json}" ]] && echo "${tags_json}" | tr -d '[:space:]' | grep -Fq "\"name\":\"${OLLAMA_MODEL}\""; then
    OLLAMA_READY="true"
    break
  fi
  if (( attempt % 12 == 0 )); then
    echo "Waiting for Ollama model ${OLLAMA_MODEL} (${attempt}/${OLLAMA_READY_RETRIES}) ..."
  fi
  sleep "${OLLAMA_READY_DELAY}"
done

if [[ "${OLLAMA_READY}" != "true" ]]; then
  echo "Ollama did not report model ${OLLAMA_MODEL} at ${OLLAMA_API_BASE} before the readiness timeout."
  echo "Confirm ingestion/model/pull_ollama.sh completed successfully."
  exit 1
fi

echo "Ollama reports ${OLLAMA_MODEL} as available."

if [[ "${RUN_PROVIDER_SMOKE_TESTS}" == "true" ]]; then
  warm_payload="{\"model\":\"${OLLAMA_MODEL}\",\"prompt\":\"Reply with OK.\",\"stream\":false,\"keep_alive\":\"30m\"}"
  curl -fsS --max-time 300 -H 'Content-Type: application/json' \
    -d "${warm_payload}" "${OLLAMA_API_BASE}/api/generate" >/dev/null
  echo "Ollama model warm-up completed."
fi

echo
echo "========================================================================"
echo "  Select AI Lab: Final Verification"
echo "========================================================================"
echo

sqlplus -s "${LAB_USER}/\"${LAB_PASSWORD_ESCAPED}\"@${DBCONNECTION}" <<SQL
whenever sqlerror exit sql.sqlcode rollback;
set define off
set verify off
set feedback on
set serveroutput on size unlimited

declare
  l_count       number;
  l_failures    number := 0;
  l_team_json   clob;
  l_response    clob;

  procedure check_min_count(p_label in varchar2, p_sql in varchar2, p_min_count in number) is
  begin
    execute immediate p_sql into l_count;
    if l_count >= p_min_count then
      dbms_output.put_line('  OK   ' || rpad(p_label, 42) || l_count);
    else
      dbms_output.put_line('  FAIL ' || rpad(p_label, 42) || l_count || ' < ' || p_min_count);
      l_failures := l_failures + 1;
    end if;
  exception
    when others then
      dbms_output.put_line('  FAIL ' || rpad(p_label, 42) || sqlerrm);
      l_failures := l_failures + 1;
  end;

  procedure check_text(p_label in varchar2, p_value in clob, p_expected in varchar2) is
  begin
    if dbms_lob.instr(p_value, p_expected) > 0 then
      dbms_output.put_line('  OK   ' || p_label);
    else
      dbms_output.put_line('  FAIL ' || p_label);
      l_failures := l_failures + 1;
    end if;
  end;
begin
  dbms_output.put_line('Checking schema data...');
  check_min_count('CUSTOMERS rows', 'select count(*) from customers', 6);
  check_min_count('PRODUCTS rows', 'select count(*) from products', 6);
  check_min_count('ORDERS rows', 'select count(*) from orders', 6);
  check_min_count('ORDER_ITEMS rows', 'select count(*) from order_items', 6);
  check_min_count('SUPPORT_CASES rows', 'select count(*) from support_cases', 4);
  check_min_count('POLICY_DOCUMENTS rows', 'select count(*) from policy_documents', 4);
  check_min_count('Order 1042', 'select count(*) from orders where order_id = 1042', 1);

  dbms_output.put_line(chr(10) || 'Checking Select AI objects...');
  check_min_count('shared ONNX model ${SHARED_MODEL_NAME}', 'select count(*) from all_mining_models where owner = ''${MODEL_OWNER_UPPER}'' and model_name = ''${MODEL_NAME_UPPER}''', 1);
  check_min_count('Policy vector index', 'select count(*) from user_cloud_vector_indexes where index_name = ''${POLICY_VECTOR_INDEX_UPPER}'' and upper(status) = ''ENABLED''', 1);
  check_min_count('Ollama profiles', 'select count(*) from user_cloud_ai_profiles where profile_name in (''SELECTAI_OLLAMA_NL2SQL'',''SELECTAI_OLLAMA_RAG'') and upper(status) = ''ENABLED''', 2);

  l_team_json := dbms_cloud_ai_agent.list_teams();
  check_text('Ollama agent team', l_team_json, 'SELECTAI_OLLAMA_TEAM');
  check_text('Custom action tool', dbms_cloud_ai_agent.describe_tool('SELECTAI_ALLOWED_ACTIONS_TOOL'), 'SELECTAI_ALLOWED_ACTIONS_TOOL');

  if '${OCI_ENABLED}' = 'true' then
    check_min_count('OCI profiles', 'select count(*) from user_cloud_ai_profiles where profile_name in (''SELECTAI_OCI_NL2SQL'',''SELECTAI_OCI_RAG'') and upper(status) = ''ENABLED''', 2);
    check_text('OCI agent team', l_team_json, 'SELECTAI_OCI_TEAM');
  end if;

  if '${RUN_PROVIDER_SMOKE_TESTS}' = 'true' then
    l_response := dbms_cloud_ai.generate(
      prompt       => 'Count the customers in the retail schema.',
      profile_name => 'SELECTAI_OLLAMA_NL2SQL',
      action       => 'SHOWSQL');
    if l_response is null or dbms_lob.getlength(l_response) = 0 then
      dbms_output.put_line('  FAIL Ollama SHOWSQL smoke test returned no response.');
      l_failures := l_failures + 1;
    else
      dbms_output.put_line('  OK   Ollama SHOWSQL provider smoke test');
    end if;

    if '${OCI_ENABLED}' = 'true' then
      l_response := dbms_cloud_ai.generate(
        prompt       => 'Count the customers in the retail schema.',
        profile_name => 'SELECTAI_OCI_NL2SQL',
        action       => 'SHOWSQL');
      if l_response is null or dbms_lob.getlength(l_response) = 0 then
        dbms_output.put_line('  FAIL OCI SHOWSQL smoke test returned no response.');
        l_failures := l_failures + 1;
      else
        dbms_output.put_line('  OK   OCI SHOWSQL provider smoke test');
      end if;
    end if;
  end if;

  if '${RUN_AGENT_SMOKE_TESTS}' = 'true' then
    l_response := dbms_cloud_ai_agent.run_team(
      team_name   => 'SELECTAI_OLLAMA_TEAM',
      user_prompt => 'For order 1042, report the delivery date and the applicable return window.');
    if l_response is null or dbms_lob.getlength(l_response) = 0 then
      dbms_output.put_line('  FAIL Ollama agent smoke test returned no response.');
      l_failures := l_failures + 1;
    else
      dbms_output.put_line('  OK   Ollama agent smoke test');
    end if;
  end if;

  if l_failures > 0 then
    insert into selectai_build_log(step_name, status, detail)
    values ('25-create-select-ai-lab', 'FAILURE', l_failures || ' verification checks failed.');
    commit;
    raise_application_error(-20062, l_failures || ' Select AI lab verification checks failed.');
  end if;

  insert into selectai_build_log(step_name, status, detail)
  values ('25-create-select-ai-lab', 'SUCCESS',
          case when '${OCI_ENABLED}' = 'true'
               then 'Ollama and OCI provider bundles provisioned.'
               else 'Ollama bundle provisioned; OCI skipped because credentials were not supplied.'
          end);
  commit;

  dbms_output.put_line(chr(10) || 'Select AI lab verification complete.');
exception
  when others then
    rollback;
    begin
      insert into selectai_build_log(step_name, status, detail)
      values ('25-create-select-ai-lab', 'FAILURE', substr(sqlerrm, 1, 4000));
      commit;
    exception
      when others then null;
    end;
    raise;
end;
/

exit;
SQL

echo
echo "========================================================================"
echo "  Select AI lab provisioning complete."
echo "  Schema: ${LAB_USER_UPPER}"
echo "  Ollama model: ${OLLAMA_MODEL}"
echo "  OCI bundle created: ${OCI_ENABLED}"
echo "========================================================================"
