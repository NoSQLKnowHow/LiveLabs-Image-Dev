#!/bin/bash
set -euo pipefail

REPO_URL="${JL_NOTEBOOKS_REPO_URL:-https://github.com/NoSQLKnowHow/LiveLabs-Image-Dev.git}"
REPO_REF="${JL_NOTEBOOKS_REPO_REF:-main}"
REPO_PATH="${JL_NOTEBOOKS_REPO_PATH:-ingestion/jl_notebooks}"
TARGET_DIR="${JL_NOTEBOOKS_TARGET_DIR:-/home/opc/ingestion/runtime/jl_notebooks}"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TARGET_DIR"

if ! command -v git >/dev/null 2>&1; then
  echo "git is required to sync JupyterLab notebooks."
  exit 1
fi

git clone \
  --depth 1 \
  --single-branch \
  --branch "$REPO_REF" \
  --filter=blob:none \
  --sparse \
  "$REPO_URL" \
  "$TMP_DIR/repo"

git -C "$TMP_DIR/repo" sparse-checkout set "$REPO_PATH"

SOURCE_DIR="$TMP_DIR/repo/$REPO_PATH"
if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Repository path not found: $REPO_PATH"
  exit 1
fi

while IFS= read -r -d '' src_file; do
  rel_path="${src_file#"$SOURCE_DIR"/}"
  mkdir -p "$TARGET_DIR/$(dirname "$rel_path")"
  cp "$src_file" "$TARGET_DIR/$rel_path"
done < <(
  find "$SOURCE_DIR" -type f \( -name '*.sql' -o -name '*.ipynb' \) -print0
)

find "$TARGET_DIR" -type d -exec chmod 0775 {} +
find "$TARGET_DIR" -type f -exec chmod 0664 {} +

echo "Synced JupyterLab notebooks from $REPO_URL/$REPO_PATH to $TARGET_DIR"
