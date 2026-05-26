#!/bin/bash

#make sure you have .env file stored in opc user home directory
# you need to provide your an placeholder for relevant passwords, and ocids, etc.
#use the demo.env and adjust values
if [[ -f /home/opc/.env ]]; then
  source /home/opc/.env
fi

export PUBLIC_IP=$(curl -s ifconfig.me)
if [[ ${#PUBLIC_IP} -le 5 || ${PUBLIC_IP} =~ '<html>' ]]; then
 export PUBLIC_IP="127.0.0.1"
fi


export vncpwd=$(curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/vncpwd)

if [[ ${#vncpwd} -ne 10 ]]; then
 export vncpwd="${vncpwdlocal:-}"
fi


export DBCONNECTION=$(curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/dbconnection|tr -d ' ')

if [[ ${#DBCONNECTION} -le 5 || ${DBCONNECTION} =~ '<html>' ]]; then
  export DBCONNECTION="${dbconnectionlocal:-}"
fi


export MONGODBAPI=$(curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/mongodbapi|tr -d ' ')

if [[ ${#MONGODBAPI} -le 5 || ${MONGODBAPI} =~ '<html>' ]]; then
 export MONGODBAPI="${mongodbapilocal:-}"
fi


export GRAPHURL=$(curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/graphurl|tr -d ' ')

if [[ ${#GRAPHURL} -le 5 || ${GRAPHURL} =~ '<html>' ]]; then
 export GRAPHURL="${graphurllocal:-}"
fi


DBPASSWORD_FROM_ENV="${DBPASSWORD:-}"
DBPASSWORD_FROM_METADATA="$(curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/dbpassword)"

if [[ ${#DBPASSWORD_FROM_METADATA} -gt 5 && ! ${DBPASSWORD_FROM_METADATA} =~ '<html>' ]]; then
 export DBPASSWORD="${DBPASSWORD_FROM_METADATA}"
else
 export DBPASSWORD="${DBPASSWORD_FROM_ENV}"
fi

export PEM_KEY=$(curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/pem_key)

if [[ ${#PEM_KEY} -le 5 || ${PEM_KEY} =~ '<html>' ]]; then
 export PEM_KEY="${pem_keylocal:-}"
fi

export PEM_SINGLE_LINE=$(echo "$PEM_KEY" | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')


export PEM_KEY_FINGERPRINT=$(curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/pem_key_fingerprint)

if [[ ${#PEM_KEY_FINGERPRINT} -le 5 || ${PEM_KEY_FINGERPRINT} =~ '<html>' ]]; then
 export PEM_KEY_FINGERPRINT="${pem_key_fingerprintlocal:-}"
fi

export USER_OCID=$(curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/user_ocid)

if [[ ${#USER_OCID} -le 5 || ${USER_OCID} =~ '<html>' ]]; then
 export USER_OCID="${user_ocidlocal:-}"
fi

export TENANCY_OCID=$(curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/tenancy_ocid)

if [[ ${#TENANCY_OCID} -le 5 || ${TENANCY_OCID} =~ '<html>' ]]; then
 export TENANCY_OCID="${tenancy_ocidlocal:-}"
fi

export REGION_IDENTIFIER=$(curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/region_identifier)

if [[ ${#REGION_IDENTIFIER} -le 5 || ${REGION_IDENTIFIER} =~ '<html>' ]]; then
 export REGION_IDENTIFIER="${region_identifierlocal:-}"
fi

export AI_ENDPOINT_REGION=$(curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/ai_endpoint_region)

if [[ ${#AI_ENDPOINT_REGION} -le 5 || ${AI_ENDPOINT_REGION} =~ '<html>' ]]; then
 export AI_ENDPOINT_REGION="${ai_endpoint_regionlocal:-}"
fi


export COMPARTMENT_OCID=$(curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/compartment_ocid)

if [[ ${#COMPARTMENT_OCID} -le 5 || ${COMPARTMENT_OCID} =~ '<html>' ]]; then
 export COMPARTMENT_OCID="${compartment_ocidlocal:-}"
fi

#workshopfiles must be a URL pointing to a zip file
export workshopfiles=$(curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/workshopfiles)

if [[ ${#workshopfiles} -ne 10 ]]; then
 export workshopfiles="https://c4u04.objectstorage.us-ashburn-1.oci.customer-oci.com/p/EcTjWk2IuZPZeNnD_fYMcgUhdNDIDA6rt9gaFj_WZMiL7VvxPBNMY60837hu5hga/n/c4u04/b/livelabsfiles/o/labfiles/vec_chunk.zip"
fi

export ENDPOINT="https://inference.generativeai.${AI_ENDPOINT_REGION}.oci.oraclecloud.com"

if [[ ${#ENDPOINT} -le 5 || "$ENDPOINT" =~ AI_ENDPOINT_REGION ]]; then
 export ENDPOINT="https://inference.generativeai.us-chicago-1.oci.oraclecloud.com"
fi

export ADB_OCID=$(curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/adb_ocid)

if [[ ${#ADB_OCID} -le 5 || ${ADB_OCID} =~ '<html>' ]]; then
 export ADB_OCID="${adb_ocidlocal:-}"
fi

export BUCKET_PAR=$(curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/bucket_par)

if [[ ${#BUCKET_PAR} -le 5 || ${BUCKET_PAR} =~ '<html>' ]]; then
 export BUCKET_PAR="https://par.par.par"
fi

export ORDSURL=$(curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/ordsurl)

if [[ ${#ORDSURL} -le 5 || ${ORDSURL} =~ '<html>' ]]; then
 export ORDSURL="${ordsurllocal:-}"
fi

export DBNAME=$(curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/dbname)

if [[ ${#DBNAME} -le 5 || ${DBNAME} =~ '<html>' ]]; then
 export DBNAME="${dbnamelocal:-}"
fi

export BUCKET_NAME=$(curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/bucket_name)

if [[ ${#BUCKET_NAME} -le 5 || ${BUCKET_NAME} =~ '<html>' ]]; then
 export BUCKET_NAME="bucket_name"
fi

export OBJECT_NAMESPACE=$(curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/object_namespace)

if [[ ${#OBJECT_NAMESPACE} -le 5 || ${OBJECT_NAMESPACE} =~ '<html>' ]]; then
 export OBJECT_NAMESPACE="ocid567890"
fi

export BASEURL=$(curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/baseurl)

if [[ ${#BASEURL} -le 5 || ${BASEURL} =~ '<html>' ]]; then
 export BASEURL="${baseurllocal:-}"
fi
