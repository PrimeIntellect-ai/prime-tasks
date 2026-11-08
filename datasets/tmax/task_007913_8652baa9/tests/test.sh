#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import uuid

import pytest

BUILD_ENV_DIR = "/home/user/build_env"
GO_SOURCE = os.path.join(BUILD_ENV_DIR, "migrate_and_merge.go")
GO_EXEC = os.path.join(BUILD_ENV_DIR, "migrate_and_merge")
PY_OUTPUT = os.path.join(BUILD_ENV_DIR, "py_output.json")
GO_OUTPUT = os.path.join(BUILD_ENV_DIR, "go_output.json")
DIFF_OUTPUT = os.path.join(BUILD_ENV_DIR, "verification_diff.txt")


def test_go_source_exists():
    assert os.path.isfile(GO_SOURCE), f"Go source file {GO_SOURCE} does not exist."
    with open(GO_SOURCE, "r") as f:
        content = f.read()
    assert "package main" in content, f"{GO_SOURCE} does not appear to be a valid Go program."


def test_go_executable_exists():
    assert os.path.isfile(GO_EXEC), f"Go executable {GO_EXEC} does not exist."
    assert os.access(GO_EXEC, os.X_OK), f"{GO_EXEC} is not executable."


def test_output_files_exist():
    assert os.path.isfile(PY_OUTPUT), f"Python output file {PY_OUTPUT} does not exist."
    assert os.path.isfile(GO_OUTPUT), f"Go output file {GO_OUTPUT} does not exist."


def test_verification_diff_empty():
    assert os.path.isfile(DIFF_OUTPUT), f"Diff output file {DIFF_OUTPUT} does not exist."
    assert os.path.getsize(DIFF_OUTPUT) == 0, f"{DIFF_OUTPUT} is not empty, indicating a difference between Go and Python outputs."
    with open(PY_OUTPUT, "rb") as py_file, open(GO_OUTPUT, "rb") as go_file:
        assert py_file.read() == go_file.read(), "The recorded Python and Go outputs actually differ."


def test_go_output_content():
    assert os.path.isfile(GO_OUTPUT), f"Go output file {GO_OUTPUT} does not exist."

    with open(GO_OUTPUT, "r") as f:
        content = f.read()

    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"{GO_OUTPUT} is not valid JSON.")

    expected_data = [
        {"id": "pkg-delta", "timestamp": 1670000050, "size_kb": 10, "schema_version": 2},
        {"id": "pkg-epsilon", "timestamp": 1670000050, "size_kb": 1, "schema_version": 2},
        {"id": "pkg-beta", "timestamp": 1670000075, "size_kb": 5, "schema_version": 2},
        {"id": "pkg-alpha", "timestamp": 1670000100, "size_kb": 2, "schema_version": 2},
        {"id": "pkg-gamma", "timestamp": 1670000100, "size_kb": 4, "schema_version": 2},
    ]

    assert data == expected_data, f"The parsed JSON in {GO_OUTPUT} does not match the expected migrated and sorted output."

    expected_str = json.dumps(expected_data, indent=2)
    assert content.strip() == expected_str.strip(), f"The formatting of {GO_OUTPUT} does not exactly match the expected 2-space indented JSON output."


def _expected(file1_items, file2_items):
    migrated = [
        {
            "id": item["id"],
            "timestamp": item["upload_time"],
            "size_kb": item["size_bytes"] // 1024,
            "schema_version": 2,
        }
        for item in file1_items + file2_items
    ]
    migrated.sort(key=lambda item: (item["timestamp"], item["id"]))
    return json.dumps(migrated, indent=2)


def _exercise(executable, workdir, file1_items, file2_items, suffix):
    input1 = workdir / f"input1-{suffix}.json"
    input2 = workdir / f"input2-{suffix}.json"
    output = workdir / f"output-{suffix}.json"
    input1.write_text(json.dumps(file1_items), encoding="utf-8")
    input2.write_text(json.dumps(file2_items), encoding="utf-8")

    result = subprocess.run(
        [str(executable), str(input1), str(input2), str(output)],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"{executable} failed: {result.stderr}"
    assert output.is_file(), f"{executable} did not create its requested output file."
    actual = output.read_text(encoding="utf-8")
    expected = _expected(file1_items, file2_items)
    assert actual.strip() == expected.strip(), f"{executable} produced incorrect migrated, sorted, or formatted output."


def test_program_executes_translation_on_unseen_inputs(tmp_path):
    rng = random.SystemRandom()
    base_time = rng.randrange(1800000000, 1900000000)
    token = uuid.uuid4().hex
    ids = [f"artifact-{token}-{letter}" for letter in ("zeta", "alpha", "mu", "beta", "omega")]

    list1 = [
        {"id": ids[0], "upload_time": base_time + 9, "size_bytes": rng.randrange(2048, 900000)},
        {"id": ids[2], "upload_time": base_time, "size_bytes": 1024 * rng.randrange(2, 200) + 1023},
        {"id": ids[4], "upload_time": base_time + 3, "size_bytes": rng.randrange(1, 1024)},
    ]
    list2 = [
        {"id": ids[1], "upload_time": base_time, "size_bytes": 1024 * rng.randrange(2, 200)},
        {"id": ids[3], "upload_time": base_time + 9, "size_bytes": rng.randrange(2048, 900000)},
    ]

    rebuilt = tmp_path / "rebuilt_migrate_and_merge"
    build = subprocess.run(
        ["go", "build", "-o", str(rebuilt), GO_SOURCE],
        cwd=BUILD_ENV_DIR,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"The submitted Go source does not build: {build.stderr}"

    _exercise(GO_EXEC, tmp_path, list1, list2, "submitted")
    _exercise(rebuilt, tmp_path, list1, list2, "rebuilt")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
