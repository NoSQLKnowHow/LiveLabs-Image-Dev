#!/bin/bash
#
# download-notebooks.sh
#
# Refresh the JupyterLab notebooks from the workshop Object Storage archive.
#
# This script is copied into /home/notebooks by the boot-time synchronizer.
# If the automatic refresh cannot reach Object Storage, open a new JupyterLab
# Terminal and run:
#
#   bash /home/notebooks/download-notebooks.sh
#
# The downloaded archive is validated before the existing notebook directory is
# replaced. Existing notebooks are preserved when a download or extraction
# fails. Set JL_NOTEBOOKS_ARCHIVE_URL or JL_NOTEBOOKS_TARGET_DIR to override the
# defaults when running the script manually.
#
set -euo pipefail

ARCHIVE_URL="${JL_NOTEBOOKS_ARCHIVE_URL:-https://objectstorage.us-ashburn-1.oraclecloud.com/p/Pg8kffjHaKzjj8pCnMbUaNmik_JBnNO-MXsaIva4iUQBFZK52oLykmY3mIhai9MS/n/axywji1aljc2/b/kirkstorage/o/dev-rel-notebooks.zip}"
SCRIPT_PATH="${BASH_SOURCE[0]}"
if [[ "$SCRIPT_PATH" != /* ]]; then
  SCRIPT_PATH="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)/$(basename -- "$SCRIPT_PATH")"
fi
SCRIPT_DIR="$(dirname -- "$SCRIPT_PATH")"
TARGET_DIR="${JL_NOTEBOOKS_TARGET_DIR:-$SCRIPT_DIR}"
MAX_ATTEMPTS=3
DOWNLOAD_TIMEOUT_SECONDS=15
RETRY_DELAY_SECONDS=1

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

ARCHIVE_PATH="$TMP_DIR/dev-rel-notebooks.zip"
STAGING_DIR="$TMP_DIR/notebooks"

download_archive() {
  local attempt
  for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
    if curl --fail --location --connect-timeout "$DOWNLOAD_TIMEOUT_SECONDS" \
      --max-time "$DOWNLOAD_TIMEOUT_SECONDS" \
      --output "$ARCHIVE_PATH" "$ARCHIVE_URL"; then
      return 0
    fi
    echo "Notebook archive download attempt ${attempt}/${MAX_ATTEMPTS} failed." >&2
    if ((attempt < MAX_ATTEMPTS)); then
      sleep "$RETRY_DELAY_SECONDS"
    fi
  done
  return 1
}

if ! download_archive; then
  echo "Notebook archive download failed after ${MAX_ATTEMPTS} attempts: $ARCHIVE_URL" >&2
  exit 1
fi

if ! unzip -tqq "$ARCHIVE_PATH"; then
  echo "Notebook archive validation failed: $ARCHIVE_URL" >&2
  exit 1
fi

if unzip -Z1 "$ARCHIVE_PATH" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
  echo "Notebook archive contains an unsafe path: $ARCHIVE_URL" >&2
  exit 1
fi

mkdir -p "$STAGING_DIR"
if ! unzip -q "$ARCHIVE_PATH" -d "$STAGING_DIR"; then
  echo "Notebook archive extraction failed: $ARCHIVE_URL" >&2
  exit 1
fi

if ! find "$STAGING_DIR" -type f -print -quit | grep -q .; then
  echo "Notebook archive is empty: $ARCHIVE_URL" >&2
  exit 1
fi

# Keep a copy because replacing TARGET_DIR also removes this running script.
cp "$SCRIPT_PATH" "$TMP_DIR/download-notebooks.sh"
mkdir -p "$TARGET_DIR"
find "$TARGET_DIR" -mindepth 1 -depth -delete
cp -a "$STAGING_DIR"/. "$TARGET_DIR"/
install -m 0755 "$TMP_DIR/download-notebooks.sh" "$TARGET_DIR/download-notebooks.sh"
find "$TARGET_DIR" -type d -exec chmod 0775 {} +
find "$TARGET_DIR" -type f ! -name download-notebooks.sh -exec chmod 0664 {} +

echo "JupyterLab notebooks refreshed from Object Storage into $TARGET_DIR"
