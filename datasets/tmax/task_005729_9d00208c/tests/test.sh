#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import subprocess
import tracemalloc
import pytest

REPO = "/home/user/log_service"
LOGFILE = "/home/user/suspicious_logs.txt"
ORACLE = "/tests/.truth_bad_commit"
EXPECTED_LINE = "WARN: [ID:999] CORRUPTED_ENTRY parse_failure_0x88"


def load_parser():
    path = os.path.join(REPO, "parser.py")
    assert os.path.isfile(path), "parser.py does not exist."
    spec = importlib.util.spec_from_file_location("submitted_parser", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_solution_json_exists():
    assert os.path.isfile("/home/user/solution.json"), "/home/user/solution.json does not exist."


def test_solution_json_content():
    with open("/home/user/solution.json", "r") as f:
        try:
            solution = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/solution.json is not valid JSON.")

    assert "bad_commit_hash" in solution, "Missing 'bad_commit_hash' in solution.json."
    assert "leaking_line_content" in solution, "Missing 'leaking_line_content' in solution.json."
    assert "fixed_successfully" in solution, "Missing 'fixed_successfully' in solution.json."

    with open(ORACLE, "r") as f:
        expected_bad_commit = f.read().strip()

    assert solution["bad_commit_hash"] == expected_bad_commit, "Incorrect bad_commit_hash."
    assert solution["leaking_line_content"] == EXPECTED_LINE, "Incorrect leaking_line_content."
    assert solution["fixed_successfully"] is True, "'fixed_successfully' should be true."


def test_test_leak_was_not_modified():
    committed = subprocess.run(
        ["git", "show", "HEAD:test_leak.py"],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    with open(os.path.join(REPO, "test_leak.py"), "r") as f:
        current = f.read()
    assert current == committed, "test_leak.py must not be modified."


def test_parser_still_processes_valid_logs():
    parser = load_parser()
    inputs = [
        "INFO: first valid entry\n",
        "\n",
        "ERROR: second valid entry\n",
    ]
    expected = [
        {"raw": "INFO: first valid entry", "status": "processed"},
        {"raw": "ERROR: second valid entry", "status": "processed"},
    ]
    assert parser.process_logs(inputs) == expected, (
        "process_logs must retain its normal parsing behavior; a no-op is not a valid fix."
    )


def test_parser_handles_corruption_without_accumulating_memory():
    parser = load_parser()
    batch = [
        "INFO: before\n",
        EXPECTED_LINE + "\n",
        "INFO: after\n",
    ]
    result = parser.process_logs(batch)
    assert isinstance(result, list), "process_logs must return a list."
    assert {"raw": "INFO: before", "status": "processed"} in result
    assert {"raw": "INFO: after", "status": "processed"} in result

    tracemalloc.start()
    for _ in range(20):
        parser.process_logs([EXPECTED_LINE + "\n"])
    current, peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    assert current < 1000000 and peak < 2000000, (
        f"Malformed entries still accumulate excessive memory (current={current}, peak={peak})."
    )


def test_leak_fixed():
    try:
        result = subprocess.run(
            ["python3", os.path.join(REPO, "test_leak.py"), LOGFILE],
            capture_output=True,
            text=True,
            cwd=REPO,
        )
    except Exception as e:
        pytest.fail(f"Failed to execute test_leak.py: {e}")

    assert result.returncode == 0, (
        f"test_leak.py exited with code {result.returncode}, meaning the leak is not fixed. "
        f"Output: {result.stdout} {result.stderr}"
    )


def test_pyyaml_dependency_fixed():
    try:
        result = subprocess.run(
            ["pip", "show", "pyyaml"],
            capture_output=True,
            text=True,
            check=True,
        )
        assert "Version: 6.0" in result.stdout, "PyYAML version 6.0 is not installed. Dependency issue not resolved."
    except subprocess.CalledProcessError:
        pytest.fail("Failed to run pip show pyyaml")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
