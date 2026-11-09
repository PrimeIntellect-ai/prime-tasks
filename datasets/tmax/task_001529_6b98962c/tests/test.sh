#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import pytest

PIPELINE_DIR = "/home/user/pipeline"
MIGRATION_PLAN = os.path.join(PIPELINE_DIR, "migration_plan.txt")
ORACLE = "/tests/expected.txt"

def test_migration_plan_exists():
    assert os.path.isfile(MIGRATION_PLAN), f"Expected output file {MIGRATION_PLAN} does not exist. Did you run the script?"

def test_migration_plan_contents():
    assert os.path.isfile(ORACLE), f"Verifier oracle {ORACLE} is missing."
    with open(MIGRATION_PLAN, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    with open(ORACLE, "r") as f:
        expected = [line.strip() for line in f if line.strip()]
    assert lines == expected, f"Contents of {MIGRATION_PLAN} are incorrect. Expected {expected}, got {lines}."

def test_make_test_succeeds():
    try:
        result = subprocess.run(
            ["make", "test"],
            cwd=PIPELINE_DIR,
            capture_output=True,
            text=True,
            check=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"'make test' failed with exit code {e.returncode}.\nStdout: {e.stdout}\nStderr: {e.stderr}")

    assert "Test Passed!" in result.stdout, "'make test' did not output 'Test Passed!'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
