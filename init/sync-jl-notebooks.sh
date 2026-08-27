#!/bin/bash
set -euo pipefail

ARCHIVE_URL="${JL_NOTEBOOKS_ARCHIVE_URL:-https://objectstorage.us-ashburn-1.oraclecloud.com/p/Pg8kffjHaKzjj8pCnMbUaNmik_JBnNO-MXsaIva4iUQBFZK52oLykmY3mIhai9MS/n/axywji1aljc2/b/kirkstorage/o/dev-rel-notebooks.zip}"
TARGET_DIR="${JL_NOTEBOOKS_TARGET_DIR:-/home/opc/ingestion/jl_notebooks}"
DOWNLOAD_SCRIPT_SOURCE="${JL_NOTEBOOKS_DOWNLOAD_SCRIPT_SOURCE:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/download-notebooks.sh}"
MAX_ATTEMPTS=3
DOWNLOAD_TIMEOUT_SECONDS=15
RETRY_DELAY_SECONDS=1

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

clear_target() {
  mkdir -p "$TARGET_DIR"
  find "$TARGET_DIR" -mindepth 1 -depth -delete
}

apply_permissions() {
  find "$TARGET_DIR" -type d -exec chmod 0775 {} +
  find "$TARGET_DIR" -type f -exec chmod 0664 {} +
}

install_manual_download_script() {
  local reason="$1"
  mkdir -p "$TARGET_DIR"
  install -m 0755 "$DOWNLOAD_SCRIPT_SOURCE" "$TARGET_DIR/download-notebooks.sh"
  rm -f "$TARGET_DIR/download-notebooks.md"
  echo "$reason"
  echo "Manual notebook download script installed at $TARGET_DIR/download-notebooks.sh"
  exit 0
}

ARCHIVE_PATH="$TMP_DIR/notebooks.zip"
STAGING_DIR="$TMP_DIR/notebooks"

download_archive() {
  local attempt
  for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
    if curl --fail --location --connect-timeout "$DOWNLOAD_TIMEOUT_SECONDS" \
      --max-time "$DOWNLOAD_TIMEOUT_SECONDS" \
      --output "$ARCHIVE_PATH" "$ARCHIVE_URL"; then
      return 0
    fi
    echo "Notebook archive download attempt ${attempt}/${MAX_ATTEMPTS} failed."
    if ((attempt < MAX_ATTEMPTS)); then
      sleep "$RETRY_DELAY_SECONDS"
    fi
  done
  return 1
}

if ! download_archive; then
  install_manual_download_script "Notebook archive download failed: $ARCHIVE_URL"
fi

if ! unzip -tqq "$ARCHIVE_PATH"; then
  install_manual_download_script "Notebook archive validation failed: $ARCHIVE_URL"
fi

if unzip -Z1 "$ARCHIVE_PATH" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
  install_manual_download_script "Notebook archive contains an unsafe path: $ARCHIVE_URL"
fi

mkdir -p "$STAGING_DIR"
if ! unzip -q "$ARCHIVE_PATH" -d "$STAGING_DIR"; then
  install_manual_download_script "Notebook archive extraction failed: $ARCHIVE_URL"
fi

if ! find "$STAGING_DIR" -type f -print -quit | grep -q .; then
  install_manual_download_script "Notebook archive is empty: $ARCHIVE_URL"
fi

clear_target
cp -a "$STAGING_DIR"/. "$TARGET_DIR"/
install -m 0755 "$DOWNLOAD_SCRIPT_SOURCE" "$TARGET_DIR/download-notebooks.sh"
apply_permissions
chmod 0755 "$TARGET_DIR/download-notebooks.sh"

echo "JupyterLab notebooks refreshed from Object Storage into $TARGET_DIR"
