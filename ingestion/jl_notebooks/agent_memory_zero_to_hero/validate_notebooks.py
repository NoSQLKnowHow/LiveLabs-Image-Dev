"""Offline notebook checks; these do not execute database/model integrations."""
import ast
import json
from pathlib import Path

import nbformat

ROOT = Path(__file__).resolve().parent
MAX_CODE_LINES = 24
REQUIRED_APIS = (
    "MemoryExtractionMode.BACKGROUND", "MemoryLinkExtractionMode.POST_EXTRACTION",
    "OracleDBEmbedder", "OracleDatabaseReranker", "link_records", "num_hops",
    "TopKMemorySearchConfig", "PruningMemorySearchConfig", "register_event_listeners",
    "list_memories", "list_threads", "get_context_card", "get_summary",
    "UserOwnRowsDeepDataSecurityPolicy", "GlobalMemoriesDeepDataSecurityPolicy",
    "create_end_user_security_context", "SchemaPolicy.NO_CHECK",
    "create_agent", "ChatOllama", "save_approved_handover", "recursion_limit",
)


def validate():
    notebooks = {}
    for edition in ("complete", "student"):
        path = ROOT / f"notebook_{edition}_ollama.ipynb"
        notebook = nbformat.read(path, as_version=4)
        nbformat.validate(notebook)
        ids = [cell.id for cell in notebook.cells]
        assert len(ids) == len(set(ids)), "Duplicate cell IDs"
        for cell in notebook.cells:
            if cell.cell_type != "code":
                continue
            assert len(cell.source.rstrip().splitlines()) <= MAX_CODE_LINES, cell.id
            assert not cell.outputs and cell.execution_count is None, cell.id
            compile(cell.source, f"{path.name}:{cell.id}", "exec",
                    flags=ast.PyCF_ALLOW_TOP_LEVEL_AWAIT)
            if edition == "complete":
                assert "NotImplementedError" not in cell.source, cell.id
        notebooks[edition] = notebook
    complete, student = notebooks["complete"], notebooks["student"]
    assert len(complete.cells) == len(student.cells)
    exercises = 0
    for solution, exercise in zip(complete.cells, student.cells):
        assert solution.id == exercise.id and solution.cell_type == exercise.cell_type
        assert solution.metadata == exercise.metadata, solution.id
        if "exercise" in solution.metadata:
            exercises += 1
            assert "NotImplementedError" in exercise.source, exercise.id
        elif solution.id != "welcome":
            assert solution.source == exercise.source, solution.id
    code = "\n".join(cell.source for cell in complete.cells if cell.cell_type == "code")
    for name in REQUIRED_APIS:
        assert name in code, f"Missing required capability: {name}"
    for forbidden in ("SchemaPolicy.RECREATE", "OllamaEmbeddings", "OPENAI_API_KEY"):
        assert forbidden not in code, f"Unexpected dependency/destructive mode: {forbidden}"
    fixture = json.loads((ROOT / "incident_data.json").read_text())
    assert {case["expected"] for case in fixture["evaluation"]} <= {
        row["id"] for row in fixture["runbooks"]
    }
    print(f"PASS: {len(complete.cells)} matched cells, {exercises} exercises; "
          f"all code cells <= {MAX_CODE_LINES} lines, valid syntax, empty outputs")


if __name__ == "__main__":
    validate()
