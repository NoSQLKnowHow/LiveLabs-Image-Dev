#!/bin/bash
set -euo pipefail

CONFIG_DIR="/etc/ords/config"

# Ensure Mongo API and Database API are explicitly enabled.
ords --config "${CONFIG_DIR}" config set mongo.enabled true
ords --config "${CONFIG_DIR}" config set database.api.enabled true

echo "Mongo API and Database API are enabled in ORDS config."
