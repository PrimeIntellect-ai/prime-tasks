#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import shutil
import stat
import subprocess
import tempfile
from functools import lru_cache


def test_c_source_exists():
    c_file = "/home/user/doc_indexer.c"
    assert os.path.isfile(c_file), f"C source file {c_file} is missing."


def test_executable_exists():
    exe_file = "/home/user/doc_indexer"
    assert os.path.isfile(exe_file), f"Executable file {exe_file} is missing."

    st = os.stat(exe_file)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), f"File {exe_file} is not executable."

    with open(exe_file, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {exe_file} is not a compiled executable."


def test_manifest_content():
    manifest_file = "/home/user/doc_manifest.txt"
    assert os.path.isfile(manifest_file), f"Manifest file {manifest_file} is missing."

    base_dir = "/home/user/docs_repo"
    expected_entries = []

    for root, dirs, files in os.walk(base_dir):
        for file in files:
            if file.endswith(".draft"):
                continue
            filepath = os.path.join(root, file)
            relpath = os.path.relpath(filepath, base_dir)

            with open(filepath, "rb") as f:
                file_hash = hashlib.sha256(f.read()).hexdigest()

            expected_entries.append((file_hash, f"./{relpath}"))

    expected_entries.sort(key=lambda x: x[0])

    with open(manifest_file, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    actual_entries = []
    for line in actual_lines:
        parts = line.split()
        assert len(parts) >= 2, f"Invalid line format in manifest: '{line}'"
        actual_entries.append((parts[0], parts[1]))

    assert len(actual_entries) == len(expected_entries), f"Expected {len(expected_entries)} entries in manifest, found {len(actual_entries)}."

    for i, (expected_hash, expected_path) in enumerate(expected_entries):
        actual_hash, actual_path = actual_entries[i]
        assert actual_hash == expected_hash, f"Line {i+1}: Expected hash {expected_hash} for {expected_path}, got {actual_hash}."
        assert actual_path == expected_path, f"Line {i+1}: Expected path {expected_path}, got {actual_path}."


@lru_cache(maxsize=1)
def compile_submitted_source():
    build_dir = tempfile.mkdtemp(prefix="doc_indexer_build_")
    output = os.path.join(build_dir, "doc_indexer")
    result = subprocess.run(
        ["gcc", "/home/user/doc_indexer.c", "-o", output],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"doc_indexer.c does not compile with GCC:\n{result.stderr}"
    assert os.path.isfile(output) and os.access(output, os.X_OK)
    return output


def expected_output(base_dir):
    lines = []
    for root, dirs, files in os.walk(base_dir):
        for name in files:
            if name.endswith(".draft"):
                continue
            path = os.path.join(root, name)
            if not os.path.isfile(path):
                continue
            with open(path, "rb") as f:
                digest = hashlib.sha256(f.read()).hexdigest()
            relpath = os.path.relpath(path, base_dir)
            lines.append(f"{digest} ./{relpath}")
    return sorted(lines)


def exercise_indexer(executable):
    base_dir = tempfile.mkdtemp(prefix="index_input_")
    try:
        os.makedirs(os.path.join(base_dir, "nested", "deeper"))
        os.makedirs(os.path.join(base_dir, "dir.draft"))

        files = {
            "root.txt": b"root-" + os.urandom(19),
            "nested/image.bin": os.urandom(73),
            "nested/keep.draft.txt": b"this is finalized despite its name",
            "nested/deeper/readme.md": b"# dynamically generated\n" + os.urandom(11),
            "dir.draft/inside.md": b"directory names are not file extensions",
            "ignored.draft": b"must not appear",
            "nested/deeper/also_ignored.draft": os.urandom(21),
        }
        for relpath, content in files.items():
            with open(os.path.join(base_dir, relpath), "wb") as f:
                f.write(content)

        result = subprocess.run(
            [executable, base_dir],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, f"Indexer failed on a valid directory:\n{result.stderr}"
        actual = result.stdout.splitlines()
        assert all(line == line.strip() and line for line in actual), "Indexer output contains blank lines or surrounding whitespace."
        assert sorted(actual) == expected_output(base_dir), f"Incorrect indexer output.\nExpected: {expected_output(base_dir)}\nActual: {sorted(actual)}"
    finally:
        shutil.rmtree(base_dir)


def test_submitted_executable_indexes_dynamic_repository():
    exercise_indexer("/home/user/doc_indexer")


def test_c_source_compiles_and_indexes_dynamic_repository():
    exercise_indexer(compile_submitted_source())


def test_manifest_matches_submitted_indexer_output():
    result = subprocess.run(
        ["/home/user/doc_indexer", "/home/user/docs_repo"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"Submitted indexer failed on docs_repo:\n{result.stderr}"
    generated = [line for line in result.stdout.splitlines() if line]
    with open("/home/user/doc_manifest.txt", "r") as f:
        manifest = [line.strip() for line in f if line.strip()]
    assert manifest == sorted(generated), "Manifest is not the sorted output of the submitted indexer."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
