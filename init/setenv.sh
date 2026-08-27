#! /bin/bash
set -euo pipefail
# This script prepares the environment variables (.env) for each app container

# source the variable file
source /home/opc/init/variable.sh

#set to your fav name
export APP_TYPE=aidata_dev_vscode_privai

export POD_ROOT=/home/opc/ingestion/
APP_DIR="$POD_ROOT/app/lab/$APP_TYPE"
COMPOSE_ENV="$POD_ROOT/.env"

# Ensure the target app directory exists before writing runtime files.
mkdir -p "$APP_DIR"


# Clean up the host OCI CLI configuration before recreating it from the current
# local fallback values or Terraform instance metadata.
sudo rm -rf /home/opc/.oci

# Create the OCI SDK/CLI configuration used by the JupyterLab container.
if [[ -z "${USER_OCID}" || -z "${PEM_KEY_FINGERPRINT}" || -z "${TENANCY_OCID}" || -z "${REGION_IDENTIFIER}" || -z "${PEM_KEY}" ]]; then
  echo "OCI user, fingerprint, tenancy, region, or PEM key is empty; cannot create OCI configuration."
  exit 1
fi

mkdir -p "$APP_DIR/.oci"

#create config
echo "[DEFAULT]" > "$APP_DIR/.oci/config"
echo "user=${USER_OCID}" >> "$APP_DIR/.oci/config"
echo "fingerprint=${PEM_KEY_FINGERPRINT}" >> "$APP_DIR/.oci/config"
echo "tenancy=${TENANCY_OCID}" >> "$APP_DIR/.oci/config"
echo "region=${REGION_IDENTIFIER}" >> "$APP_DIR/.oci/config"
echo "key_file=~/.oci/oci_api_key.pem" >> "$APP_DIR/.oci/config"

printf '%s\n' "$PEM_KEY" > "$APP_DIR/.oci/oci_api_key.pem"
chmod 700 "$APP_DIR/.oci"
chmod 600 "$APP_DIR/.oci/config" "$APP_DIR/.oci/oci_api_key.pem"

# copy keys to ~/.oci/
install -d -m 700 /home/opc/.oci
install -m 600 "$APP_DIR/.oci/config" /home/opc/.oci/config
install -m 600 "$APP_DIR/.oci/oci_api_key.pem" /home/opc/.oci/oci_api_key.pem

# The password baked into the image is authoritative. The local .env value is
# used only during the initial setup when .vncpwd does not exist yet.
if [[ -s "$APP_DIR/.vncpwd" ]]; then
  IFS= read -r vncpwd < "$APP_DIR/.vncpwd"
elif [[ -n "${vncpwd:-}" ]]; then
  printf '%s\n' "$vncpwd" > "$APP_DIR/.vncpwd"
else
  echo "Missing JupyterLab password: $APP_DIR/.vncpwd does not exist and no local vncpwd value was provided."
  exit 1
fi

if [[ -z "$vncpwd" ]]; then
  echo "JupyterLab password in $APP_DIR/.vncpwd is empty."
  exit 1
fi

printf 'vncpwd=%s\n' "$vncpwd" > "$APP_DIR/.vncpwd.env"
chmod 600 "$APP_DIR/.vncpwd" "$APP_DIR/.vncpwd.env"
install -m 600 "$APP_DIR/.vncpwd.env" /home/opc/.vncpwd.env

# Resolve one canonical DB password for all generated config files.
ORACLE_PWD_VALUE="${DBPASSWORD:-${ORACLE_PWD:-}}"
if [[ -z "${ORACLE_PWD_VALUE}" ]]; then
  echo "DBPASSWORD and ORACLE_PWD are empty; cannot start DB/ORDS containers."
  exit 1
fi

#.env file for jupyterlab 
# echo -e "PEM_KEY=\"${PEM_KEY}\"" > "$APP_DIR/.env"
> "$APP_DIR/.env"
echo "USERNAME=admin" >> "$APP_DIR/.env"
echo "DBPASSWORD=${ORACLE_PWD_VALUE}" >> "$APP_DIR/.env"
echo "PASSWORD=${ORACLE_PWD_VALUE}" >> "$APP_DIR/.env"
echo "DBCONNECTION=\"${DBCONNECTION}\"" >> "$APP_DIR/.env"
echo "MONGODBAPI=\"${MONGODBAPI}\"" >> "$APP_DIR/.env"
# echo "GRAPHURL=${GRAPHURL}" >> "$APP_DIR/.env"
echo "PUBLIC_IP=${PUBLIC_IP}" >> "$APP_DIR/.env"
echo "COMPARTMENT_OCID=${COMPARTMENT_OCID}" >> "$APP_DIR/.env"
echo "ENDPOINT=${ENDPOINT}" >> "$APP_DIR/.env"
# echo "ADB_OCID=${ADB_OCID}" >> "$APP_DIR/.env"
echo "user=${USER_OCID}" >> "$APP_DIR/.env"
echo "fingerprint=${PEM_KEY_FINGERPRINT}" >> "$APP_DIR/.env"
echo "tenancy=${TENANCY_OCID}" >> "$APP_DIR/.env"
echo "region=${REGION_IDENTIFIER}" >> "$APP_DIR/.env"
echo "key_file=~/.oci/oci_api_key.pem" >> "$APP_DIR/.env"
echo "dbname=${DBNAME}" >> "$APP_DIR/.env"
# echo "ORDSURL=${ORDSURL}" >> "$APP_DIR/.env"
# echo "SERVICE_NAME=${DBNAME}_high" >> "$APP_DIR/.env"
# echo "BUCKET_PAR=${BUCKET_PAR}" >> "$APP_DIR/.env"
# echo "BUCKET_NAME=${BUCKET_NAME}" >> "$APP_DIR/.env"
# echo "OBJECT_NAMESPACE=${OBJECT_NAMESPACE}" >> "$APP_DIR/.env"
# echo "BASEURL=${BASEURL}" >> "$APP_DIR/.env"
# echo OJDBC_PATH="/wallet" >> "$APP_DIR/.env"
echo "AI_ENDPOINT_REGION=${AI_ENDPOINT_REGION}" >> "$APP_DIR/.env"
echo "USER_OCID=${USER_OCID}" >> "$APP_DIR/.env"
echo "TENANCY_OCID=${TENANCY_OCID}" >> "$APP_DIR/.env"
echo "PEM_KEY_FINGERPRINT=${PEM_KEY_FINGERPRINT}" >> "$APP_DIR/.env"
echo "PEM_SINGLE_LINE=\"${PEM_SINGLE_LINE}\"" >> "$APP_DIR/.env"
echo "workshopfiles=${workshopfiles}" >> "$APP_DIR/.env"
chmod 600 "$APP_DIR/.env"

# Compose variable interpolation for DB/ORDS containers.
printf 'ORACLE_PWD=%s\n' "${ORACLE_PWD_VALUE}" > "${COMPOSE_ENV}"
printf 'APP_DB_ADMIN_PWD=%s\n' "${ORACLE_PWD_VALUE}" >> "${COMPOSE_ENV}"
chmod 600 "${COMPOSE_ENV}"


# Tighten app permissions: owner-access only.
chmod -R u=rwX,go= "$POD_ROOT/app/"

#JupyterLab default settings
# mkdir -p $POD_ROOT/app/lab/$APP_TYPE/.jupyter
# cp -r $POD_ROOT/jl_config/* $POD_ROOT/app/lab/$APP_TYPE/.jupyter
