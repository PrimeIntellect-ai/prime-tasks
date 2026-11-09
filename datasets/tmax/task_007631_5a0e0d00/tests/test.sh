#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
from pathlib import Path

BASE_DIR = Path("/home/user/messy_project")
ALL_CODE_PATH = Path("/home/user/all_code.py")
CHUNKS_DIR = Path("/home/user/chunks")

EXPECTED_SOURCES = {
    BASE_DIR / "lib/utils/helper.py": "".join(f'print("Helper line {i}")\n' for i in range(1, 31)),
    BASE_DIR / "src/app.py": "".join(f'print("App line {i}")\n' for i in range(1, 26)),
    BASE_DIR / "src/core/main.py": "".join(f'print("Main line {i}")\n' for i in range(1, 61)),
}


def test_renamed_files():
    # note1.txt should remain untouched
    note1_path = BASE_DIR / "docs/note1.txt"
    assert note1_path.is_file(), f"File should be untouched: {note1_path}"

    # note2.txt and todo_list.txt should be renamed to .todo
    note2_todo = BASE_DIR / "docs/note2.todo"
    todo_list_todo = BASE_DIR / "src/todo_list.todo"
    note2_txt = BASE_DIR / "docs/note2.txt"
    todo_list_txt = BASE_DIR / "src/todo_list.txt"

    assert note2_todo.is_file(), f"File not found or not renamed properly: {note2_todo}"
    assert todo_list_todo.is_file(), f"File not found or not renamed properly: {todo_list_todo}"
    assert not note2_txt.exists(), f"Original file should not exist: {note2_txt}"
    assert not todo_list_txt.exists(), f"Original file should not exist: {todo_list_txt}"

    # Renaming must preserve the original contents and leave nonmatching text files untouched.
    assert note1_path.read_text() == "This is a clean note.\n"
    assert note2_todo.read_text() == "TODO: refactor the core module.\n"
    assert todo_list_todo.read_text() == "Another TODO item here.\n"

    remaining_txt = {p for p in BASE_DIR.rglob("*.txt") if p.is_file()}
    todo_files = {p for p in BASE_DIR.rglob("*.todo") if p.is_file()}
    assert remaining_txt == {note1_path}
    assert todo_files == {note2_todo, todo_list_todo}


def test_all_code_file():
    assert ALL_CODE_PATH.is_file(), f"Merged file not found: {ALL_CODE_PATH}"

    # Ensure the original Python inputs were preserved and no substitute inputs were added.
    actual_sources = {p for p in BASE_DIR.rglob("*.py") if p.is_file()}
    assert actual_sources == set(EXPECTED_SOURCES)
    for path, expected_content in EXPECTED_SOURCES.items():
        assert path.read_text() == expected_content, f"Source file was altered: {path}"

    expected_merged = "".join(EXPECTED_SOURCES[path] for path in sorted(EXPECTED_SOURCES, key=str))
    actual_merged = ALL_CODE_PATH.read_text()
    assert actual_merged == expected_merged, "Merged file is not the exact ordered concatenation of all Python files"

    lines = actual_merged.splitlines()
    assert len(lines) == 115, f"Expected 115 lines in {ALL_CODE_PATH}, found {len(lines)}"

    # Check alphabetical ordering based on absolute paths.
    assert lines[0] == 'print("Helper line 1")', "First line does not match expected output from helper.py"
    assert lines[30] == 'print("App line 1")', "Line 31 does not match expected output from app.py"
    assert lines[55] == 'print("Main line 1")', "Line 56 does not match expected output from main.py"


def test_chunks():
    assert CHUNKS_DIR.is_dir(), f"Chunks directory not found: {CHUNKS_DIR}"

    chunk_00 = CHUNKS_DIR / "chunk_00.py"
    chunk_01 = CHUNKS_DIR / "chunk_01.py"
    chunk_02 = CHUNKS_DIR / "chunk_02.py"

    assert chunk_00.is_file(), f"Chunk file missing: {chunk_00}"
    assert chunk_01.is_file(), f"Chunk file missing: {chunk_01}"
    assert chunk_02.is_file(), f"Chunk file missing: {chunk_02}"

    with chunk_00.open() as f:
        assert len(f.readlines()) == 50, f"Expected 50 lines in {chunk_00}"
    with chunk_01.open() as f:
        assert len(f.readlines()) == 50, f"Expected 50 lines in {chunk_01}"
    with chunk_02.open() as f:
        assert len(f.readlines()) == 15, f"Expected 15 lines in {chunk_02}"

    all_chunks = [f for f in os.listdir(CHUNKS_DIR) if f.startswith("chunk_") and f.endswith(".py")]
    assert len(all_chunks) == 3, f"Expected exactly 3 chunk files, found {len(all_chunks)}"

    merged_lines = ALL_CODE_PATH.read_text().splitlines(keepends=True)
    expected_chunks = [
        "".join(merged_lines[0:50]),
        "".join(merged_lines[50:100]),
        "".join(merged_lines[100:115]),
    ]
    for path, expected_content in zip((chunk_00, chunk_01, chunk_02), expected_chunks):
        assert path.read_text() == expected_content, f"Chunk does not match the corresponding merged-file segment: {path}"

    assert sorted(all_chunks) == ["chunk_00.py", "chunk_01.py", "chunk_02.py"]
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
