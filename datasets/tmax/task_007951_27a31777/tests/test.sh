#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
import tempfile
from decimal import Decimal
from pathlib import Path

SCRIPT_PATH = Path("/home/user/run_search.sh")
RESULT_PATH = Path("/home/user/stable_k.txt")
OUTPUT_PATH = Path("/home/user/output.ipynb")
SOURCE_PATH = Path("/home/user/simulate.ipynb")


def make_fake_papermill(fake_bin: Path):
    papermill = fake_bin / "papermill"
    papermill.write_text(r'''#!/usr/bin/env python3
import json
import os
import sys
from decimal import Decimal, InvalidOperation
from pathlib import Path

args = sys.argv[1:]
value = None
for i, arg in enumerate(args):
    if arg in ("-p", "--parameters", "-r", "--parameters_raw") and i + 2 < len(args):
        if args[i + 1] == "k":
            value = args[i + 2]
            break

valid_paths = len(args) >= 2 and args[0] == "/home/user/simulate.ipynb" and args[1] == "/home/user/output.ipynb"
formatted = None
try:
    if value is not None:
        formatted = format(Decimal(value), ".2f")
except InvalidOperation:
    pass

with open(os.environ["PM_LOG"], "a") as log:
    log.write(json.dumps({"args": args, "k": formatted, "valid_paths": valid_paths}) + "\n")

if not valid_paths or formatted is None:
    print("FAKE_PAPERMILL_FAILURE: malformed invocation", file=sys.stderr)
    sys.exit(64)

if formatted != os.environ["PM_SUCCESS_K"]:
    print("FAKE_PAPERMILL_FAILURE: simulated notebook error", file=sys.stderr)
    sys.exit(1)

notebook = {
    "cells": [],
    "metadata": {"verifier_k": formatted, "executed_by": "papermill-test-double"},
    "nbformat": 4,
    "nbformat_minor": 4
}
Path("/home/user/output.ipynb").write_text(json.dumps(notebook))
sys.exit(0)
''')
    papermill.chmod(papermill.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def run_scenario(success_k: str):
    RESULT_PATH.unlink(missing_ok=True)
    OUTPUT_PATH.unlink(missing_ok=True)

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        fake_bin = tmp_path / "bin"
        fake_bin.mkdir()
        make_fake_papermill(fake_bin)
        log_path = tmp_path / "calls.jsonl"

        env = os.environ.copy()
        env["PATH"] = str(fake_bin) + os.pathsep + env.get("PATH", "")
        env["PM_LOG"] = str(log_path)
        env["PM_SUCCESS_K"] = success_k

        completed = subprocess.run(
            [str(SCRIPT_PATH)],
            cwd="/home/user",
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=45,
        )

        assert completed.returncode == 0, (
            f"run_search.sh exited with {completed.returncode}. stderr: {completed.stderr}"
        )
        assert "FAKE_PAPERMILL_FAILURE" not in completed.stderr, (
            "papermill error output from failed attempts was not suppressed"
        )
        assert log_path.is_file(), "run_search.sh did not invoke papermill"

        calls = [json.loads(line) for line in log_path.read_text().splitlines() if line.strip()]
        expected_count = int(Decimal(success_k) * 100)
        expected_values = [f"{i / 100:.2f}" for i in range(1, expected_count + 1)]
        actual_values = [call["k"] for call in calls]

        assert actual_values == expected_values, (
            f"Expected papermill attempts {expected_values}, got {actual_values}"
        )
        assert all(call["valid_paths"] for call in calls), (
            "Every papermill call must use /home/user/simulate.ipynb as input and "
            "/home/user/output.ipynb as output"
        )

        assert RESULT_PATH.is_file(), "stable_k.txt was not created after a successful execution"
        assert RESULT_PATH.read_text().strip() == success_k, (
            f"Expected stable_k.txt to contain {success_k} in this scenario"
        )
        assert OUTPUT_PATH.is_file(), "The successful papermill invocation did not produce output.ipynb"
        notebook = json.loads(OUTPUT_PATH.read_text())
        assert notebook.get("nbformat") == 4, "output.ipynb is not a valid notebook-shaped JSON file"
        assert notebook.get("metadata", {}).get("verifier_k") == success_k, (
            "output.ipynb was not produced by the successful papermill invocation"
        )


def test_search_behavior_and_execution():
    """Execute the submitted script and verify its search behavior without trusting a hardcoded answer."""
    assert SOURCE_PATH.is_file(), f"Missing source notebook: {SOURCE_PATH}"
    assert SCRIPT_PATH.is_file(), f"Missing required script file: {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script file {SCRIPT_PATH} is not executable."

    # An alternate success point catches scripts that merely hardcode the known answer.
    run_scenario("0.23")
    # Leave the required ground-truth final state in place for the original assertions.
    run_scenario("0.17")


def test_run_search_script_exists_and_executable():
    """Test that the run_search.sh script exists and is executable."""
    script_path = "/home/user/run_search.sh"
    assert os.path.isfile(script_path), f"Missing required script file: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script file {script_path} is not executable."


def test_stable_k_file():
    """Test that stable_k.txt exists and contains the correct value."""
    result_path = "/home/user/stable_k.txt"
    assert os.path.isfile(result_path), f"Missing result file: {result_path}"

    with open(result_path, "r") as f:
        content = f.read().strip()

    assert content == "0.17", f"Expected stable_k.txt to contain '0.17', but found '{content}'."


def test_output_notebook_exists():
    """Test that the output notebook was generated."""
    output_path = "/home/user/output.ipynb"
    assert os.path.isfile(output_path), f"Missing output notebook file: {output_path}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
