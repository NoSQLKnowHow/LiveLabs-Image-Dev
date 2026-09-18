#!/bin/bash
set -euo pipefail

if [[ "$(id -un)" != "opc" ]]; then
  echo "Run this script as the opc user, not with sudo."
  exit 1
fi

UPDATE_ARCHIVE="/home/opc/build_dev.zip"
DB_STARTUP_DIR="/home/opc/ingestion/db-startup"
COMPOSE_FILE="/home/opc/ingestion/compose.yml"
USER_SERVICE_TARGET="/home/opc/.config/systemd/user/user-podman.service"
SETENV_TARGET="/home/opc/init/setenv.sh"
CONTAINER_DB_STARTUP_DIR="/tmp/db-startup"
BOOTSTRAP_MARKER="/home/opc/ingestion/runtime/db-startup-complete"
LOG_DIR="/home/opc/ingestion/runtime/logs"
# Oracle Linux's journalctl accepts this format consistently, unlike a
# numeric-UTC-offset ISO timestamp on some installed systemd versions.
RUN_STARTED_AT="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

install -d -m 0700 "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/inst3-$(date +%Y%m%dT%H%M%S%z).log"
touch "${LOG_FILE}"
chmod 0600 "${LOG_FILE}"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "Logging this inst3 run to ${LOG_FILE}"

if [[ ! -f "${UPDATE_ARCHIVE}" ]]; then
  echo "Update ZIP was not found: ${UPDATE_ARCHIVE}"
  exit 1
fi

STAGING_DIR="$(mktemp -d)"
cleanup() {
  local exit_status=$?

  echo
  echo "========================================================================"
  echo "  user-podman.service journal entries for this inst3 run"
  echo "========================================================================"
  journalctl --user -u user-podman.service --since "${RUN_STARTED_AT}" --no-pager || true
  echo "inst3 log saved to ${LOG_FILE}"
  rm -rf "${STAGING_DIR}"
  return "${exit_status}"
}
trap cleanup EXIT

# Copy only the Compose definition and setup scripts. Do not overwrite oradata,
# .env files, notebooks, or other instance-specific runtime data from the update
# archive.
unzip -qq "${UPDATE_ARCHIVE}" 'ingestion/compose.yml' 'init/setenv.sh' 'init/user-podman.service' 'ingestion/db-startup/*.sh' -d "${STAGING_DIR}"
if [[ ! -f "${STAGING_DIR}/ingestion/compose.yml" ]]; then
  echo "ingestion/compose.yml was not found in ${UPDATE_ARCHIVE}."
  exit 1
fi
if [[ ! -f "${STAGING_DIR}/init/user-podman.service" ]]; then
  echo "init/user-podman.service was not found in ${UPDATE_ARCHIVE}."
  exit 1
fi
if [[ ! -f "${STAGING_DIR}/init/setenv.sh" ]]; then
  echo "init/setenv.sh was not found in ${UPDATE_ARCHIVE}."
  exit 1
fi
shopt -s nullglob
setup_scripts=("${STAGING_DIR}"/ingestion/db-startup/*.sh)
if (( ${#setup_scripts[@]} == 0 )); then
  echo "No ingestion/db-startup/*.sh files were found in ${UPDATE_ARCHIVE}."
  exit 1
fi

for setup_script in "${setup_scripts[@]}"; do
  if ! awk '
    /sqlplus.*<<SQL/ { sqlplus_heredocs++ }
    /^SQL$/ { sql_terminators++ }
    END { exit sqlplus_heredocs == sql_terminators ? 0 : 1 }
  ' "${setup_script}"; then
    echo "Refusing to install $(basename "${setup_script}"): SQL*Plus here-document count does not match SQL terminator count."
    exit 1
  fi
done

install -d -m 0755 "${DB_STARTUP_DIR}"
install -m 0755 "${setup_scripts[@]}" "${DB_STARTUP_DIR}/"
install -m 0644 "${STAGING_DIR}/ingestion/compose.yml" "${COMPOSE_FILE}"
install -m 0755 "${STAGING_DIR}/init/setenv.sh" "${SETENV_TARGET}"
install -d -m 0755 "$(dirname "${USER_SERVICE_TARGET}")"
install -m 0644 "${STAGING_DIR}/init/user-podman.service" "${USER_SERVICE_TARGET}"
echo "Installed ${#setup_scripts[@]} database startup script(s) from ${UPDATE_ARCHIVE}."
echo "Installed the updated Compose definition from ${UPDATE_ARCHIVE}."
echo "Installed the updated environment setup script from ${UPDATE_ARCHIVE}."
echo "Installed the updated user-podman systemd service from ${UPDATE_ARCHIVE}."

# Database startup files must not be bind-mounted into the database container.
# The image has its own startup-script discovery mechanism, while these are
# Bash scripts that inst3 invokes explicitly after the database is ready.
if sed '/^[[:space:]]*#/d' "${COMPOSE_FILE}" | grep -Fq './db-startup:'; then
  echo "Refusing to start: ${COMPOSE_FILE} still bind-mounts ingestion/db-startup into aidbfree."
  exit 1
fi

export XDG_RUNTIME_DIR="/run/user/$(id -u)"

systemctl --user daemon-reload
if systemctl --user is-active --quiet user-podman.service; then
  echo "Stopping the existing Compose service before database-only startup."
  systemctl --user stop user-podman.service
fi

# Bring up the database and Ollama first. A full podman-compose up may spend
# many minutes building JupyterLab before it reaches aidbfree, which would make
# the database readiness wait time out even though the database has not failed.
# The Select AI RAG vector-index pipeline needs its complete Ollama profile.
echo "Preparing Compose settings and starting aidbfree and ollama ..."
/home/opc/init/setenv.sh
(cd /home/opc/ingestion && /usr/local/bin/podman-compose up -d aidbfree ollama)

wait_for_database() {
  local attempt
  local total_attempts=360

  for ((attempt = 1; attempt <= total_attempts; attempt++)); do
    if podman exec aidbfree bash -c 'sqlplus -L -s / as sysdba <<SQL >/dev/null 2>&1
whenever sqlerror exit 1
declare
  l_cdb_open_mode varchar2(20);
  l_pdb_open_mode varchar2(20);
begin
  select open_mode
    into l_cdb_open_mode
    from v\$database;

  select open_mode
    into l_pdb_open_mode
    from v\$pdbs
   where name = '\''FREEPDB1'\'';

  if l_cdb_open_mode <> '\''READ WRITE'\'' or l_pdb_open_mode <> '\''READ WRITE'\'' then
    raise_application_error(-20001,
      '\''Database is not fully open: CDB='\'' || l_cdb_open_mode || '\'', PDB='\'' || l_pdb_open_mode);
  end if;
end;
/
exit
SQL' >/dev/null 2>&1; then
      return 0
    fi

    if (( attempt == 1 || attempt % 12 == 0 )); then
      echo "Waiting for aidbfree SYSDBA readiness (${attempt}/${total_attempts}, up to 30 minutes) ..."
      podman ps -a --filter name='^aidbfree$' --format 'aidbfree status: {{.Status}}' || true
    fi
    sleep 5
  done

  return 1
}

show_database_startup_diagnostics() {
  echo "========================================================================"
  echo "  aidbfree startup diagnostics"
  echo "========================================================================"
  podman ps -a --filter name='^aidbfree$' || true
  podman logs --tail 200 aidbfree 2>&1 || true
  echo "========================================================================"
  echo "  user-podman.service diagnostics"
  echo "========================================================================"
  systemctl --user --no-pager --full status user-podman.service || true
  journalctl --user -u user-podman.service -n 200 --no-pager || true
}

bootstrap_schemas_ready() {
  local schema_count

  schema_count="$(podman exec -i aidbfree sqlplus -L -s / as sysdba <<'SQL' |
    awk '/^[[:space:]]*[0-9]+[[:space:]]*$/ {gsub(/[[:space:]]/, "", $0); print; exit}'
set heading off feedback off pages 0 verify off
alter session set container = FREEPDB1;
select count(*)
  from dba_users
 where username in ('PRISM', 'SELECTAI_LAB');
exit
SQL
)" || return 1

  [[ "${schema_count}" == "2" ]]
}

if [[ -f "${BOOTSTRAP_MARKER}" ]] && wait_for_database && bootstrap_schemas_ready; then
  echo "Database startup scripts already completed on this instance."
  echo "Run an individual changed script manually when needed."
else
  if [[ -f "${BOOTSTRAP_MARKER}" ]]; then
    echo "Ignoring stale database-startup-complete marker because PRISM and SELECTAI_LAB are not both present."
    rm -f "${BOOTSTRAP_MARKER}"
  fi

  echo "Waiting for aidbfree to accept SYSDBA connections ..."
  if ! wait_for_database; then
    echo "aidbfree did not become ready within 30 minutes."
    show_database_startup_diagnostics
    exit 1
  fi

  db_startup_mounts="$(podman inspect aidbfree --format '{{range .Mounts}}{{printf "%s -> %s\\n" .Source .Destination}}{{end}}')"
  echo "aidbfree mounts:"
  printf '%s\n' "${db_startup_mounts}"
  if grep -Fq -- '-> /opt/oracle/scripts/setup' <<<"${db_startup_mounts}" || \
     grep -Fq -- '-> /opt/oracle/scripts/startup' <<<"${db_startup_mounts}"; then
    echo "Refusing to run startup scripts: aidbfree has an Oracle automatic-startup directory mounted."
    exit 1
  fi
  if grep -Fq -- "${DB_STARTUP_DIR} ->" <<<"${db_startup_mounts}"; then
    echo "Refusing to run startup scripts: aidbfree still has the host db-startup directory mounted."
    exit 1
  fi

  shopt -s nullglob
  startup_scripts=("${DB_STARTUP_DIR}"/*.sh)
  if (( ${#startup_scripts[@]} == 0 )); then
    echo "No database startup shell scripts were found in ${DB_STARTUP_DIR}."
    exit 1
  fi

  echo "Copying database startup scripts into ${CONTAINER_DB_STARTUP_DIR} ..."
  podman exec aidbfree bash -c "rm -rf '${CONTAINER_DB_STARTUP_DIR}' && install -d -m 0755 '${CONTAINER_DB_STARTUP_DIR}'"
  for host_script in "${startup_scripts[@]}"; do
    script_name="$(basename "${host_script}")"
    podman cp "${host_script}" "aidbfree:${CONTAINER_DB_STARTUP_DIR}/${script_name}"
  done

  for host_script in "${startup_scripts[@]}"; do
    script_name="$(basename "${host_script}")"
    echo "Running ${script_name} in aidbfree with Bash ..."
    podman exec aidbfree bash "${CONTAINER_DB_STARTUP_DIR}/${script_name}"
  done

  if ! bootstrap_schemas_ready; then
    echo "Database startup did not create both PRISM and SELECTAI_LAB. The completion marker was not written."
    exit 1
  fi

  touch "${BOOTSTRAP_MARKER}"
  echo "Database startup scripts completed successfully."
fi

echo "Starting the full Podman Compose service ..."
systemctl --user enable user-podman.service
systemctl --user start user-podman.service

echo "Podman Compose has been started. Follow service status with:"
echo "  systemctl --user status user-podman.service"
echo "  journalctl --user -u user-podman.service -f"
