#!/bin/bash
set -euo pipefail

REPO_URL="${JL_NOTEBOOKS_REPO_URL:-https://github.com/NoSQLKnowHow/LiveLabs-Image-Dev.git}"
REPO_REF="${JL_NOTEBOOKS_REPO_REF:-main}"
REPO_PATH="${JL_NOTEBOOKS_REPO_PATH:-ingestion/jl_notebooks}"
LOCAL_SOURCE_DIR="${JL_NOTEBOOKS_LOCAL_SOURCE_DIR:-/home/opc/ingestion/jl_notebooks}"
TARGET_DIR="${JL_NOTEBOOKS_TARGET_DIR:-/home/opc/ingestion/runtime/jl_notebooks}"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TARGET_DIR"

copy_notebook_files() {
  local source_dir="$1"
  local source_label="$2"
  local copied=0

  if [[ ! -d "$source_dir" ]]; then
    echo "Skipping $source_label notebooks; source directory not found: $source_dir"
    return 1
  fi

  while IFS= read -r -d '' src_file; do
    rel_path="${src_file#"$source_dir"/}"
    mkdir -p "$TARGET_DIR/$(dirname "$rel_path")"
    cp "$src_file" "$TARGET_DIR/$rel_path"
    copied=$((copied + 1))
  done < <(
    find "$source_dir" -type f \( -name '*.sql' -o -name '*.ipynb' \) -print0
  )

  if [[ "$copied" -eq 0 ]]; then
    echo "No .sql or .ipynb files found in $source_label source: $source_dir"
    return 1
  fi

  echo "Copied $copied $source_label notebook file(s) into $TARGET_DIR"
  return 0
}

apply_permissions() {
  find "$TARGET_DIR" -type d -exec chmod 0775 {} +
  find "$TARGET_DIR" -type f -exec chmod 0664 {} +
}

synced_any=0

if copy_notebook_files "$LOCAL_SOURCE_DIR" "local packaged"; then
  synced_any=1
fi

if command -v git >/dev/null 2>&1; then
  if git clone \
    --depth 1 \
    --single-branch \
    --branch "$REPO_REF" \
    --filter=blob:none \
    --sparse \
    "$REPO_URL" \
    "$TMP_DIR/repo"; then

    if git -C "$TMP_DIR/repo" sparse-checkout set "$REPO_PATH"; then
      SOURCE_DIR="$TMP_DIR/repo/$REPO_PATH"
      if copy_notebook_files "$SOURCE_DIR" "GitHub"; then
        synced_any=1
      else
        echo "GitHub checkout did not provide usable notebook files; keeping local packaged files."
      fi
    else
      echo "GitHub sparse checkout failed; keeping local packaged files."
    fi
  else
    echo "GitHub clone failed; keeping local packaged files."
  fi
else
  echo "git is not installed; keeping local packaged files."
fi

apply_permissions

if [[ "$synced_any" -eq 0 ]]; then
  echo "No JupyterLab notebooks were copied from local package or GitHub."
  exit 1
fi

echo "JupyterLab notebooks are ready in $TARGET_DIR"
