#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
"${PYTHON_BIN:-python3}" -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m pip check
.venv/bin/python -m ipykernel install --user \
  --name agent-memory-26-8 --display-name 'Agent Memory 26.8 (Ollama)'
echo 'Select Agent Memory 26.8 (Ollama) in Jupyter before opening the lab.'
