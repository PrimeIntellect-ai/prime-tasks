#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import base64
import json
import os
import pickle
import secrets
import subprocess
import tempfile

import pytest

SCRIPT = "/home/user/log_aggregator.py"
SUMMARY = "/home/user/summary.txt"
CONFIG = "/home/user/config.dat"
SERVER_LOG = "/home/user/server.log"
VALID_TOKEN = "DEVOPS_SECRET_2023"


def read_summary():
    assert os.path.isfile(SUMMARY), f"The file {SUMMARY} was not generated. Did you run the script successfully?"
    with open(SUMMARY, "r") as f:
        content = f.read().strip()
    try:
        return ast.literal_eval(content)
    except Exception as e:
        pytest.fail(f"Failed to parse the contents of {SUMMARY}. Expected a dictionary string. Error: {e}")


def test_00_log_aggregator_actually_runs_and_uses_token_and_config():
    """Execute the repaired artifact against verifier-generated data."""
    assert os.path.isfile(SCRIPT), f"Missing {SCRIPT}"

    level_a = "VERIFY_" + secrets.token_hex(8)
    level_b = "VERIFY_" + secrets.token_hex(8)
    ignored = "IGNORE_" + secrets.token_hex(8)
    count_a = secrets.randbelow(5) + 1
    count_b = secrets.randbelow(5) + 1
    expected = {level_a: count_a, level_b: count_b}

    entries = ([{"level": level_a, "msg": "a"}] * count_a +
               [{"level": level_b, "msg": "b"}] * count_b +
               [{"level": ignored, "msg": "ignored"}])
    secrets.SystemRandom().shuffle(entries)

    with open(CONFIG, "rb") as f:
        original_config = f.read()

    fd, generated_log = tempfile.mkstemp(prefix="aggregation-", suffix=".log")
    os.close(fd)
    try:
        with open(CONFIG, "wb") as f:
            f.write(base64.b64encode(pickle.dumps({"levels": [level_a, level_b]})))
        with open(generated_log, "w") as f:
            for entry in entries:
                f.write(json.dumps(entry) + "\n")

        if os.path.exists(SUMMARY):
            os.remove(SUMMARY)
        bad = subprocess.run(
            ["python3", SCRIPT, generated_log, "DEFINITELY_WRONG_" + secrets.token_hex(8)],
            text=True, capture_output=True, timeout=15
        )
        assert bad.returncode != 0, "The script accepted an invalid security token."
        assert not os.path.exists(SUMMARY), "The script generated a summary despite an invalid token."

        good = subprocess.run(
            ["python3", SCRIPT, generated_log, VALID_TOKEN],
            text=True, capture_output=True, timeout=15
        )
        assert good.returncode == 0, (
            f"The required command failed. stdout={good.stdout!r}, stderr={good.stderr!r}"
        )
        assert read_summary() == expected, (
            f"Generated-data summary is incorrect. Expected {expected}, got {read_summary()}."
        )
    finally:
        with open(CONFIG, "wb") as f:
            f.write(original_config)
        if os.path.exists(generated_log):
            os.remove(generated_log)

    # Also execute the exact command and original inputs required by the instruction.
    if os.path.exists(SUMMARY):
        os.remove(SUMMARY)
    original = subprocess.run(
        ["python3", SCRIPT, SERVER_LOG, VALID_TOKEN],
        text=True, capture_output=True, timeout=15
    )
    assert original.returncode == 0, (
        f"Execution on server.log failed. stdout={original.stdout!r}, stderr={original.stderr!r}"
    )
    assert read_summary() == {'ERROR': 2, 'CRITICAL': 1}


def test_summary_file_exists_and_correct():
    """Test that the summary.txt file was generated and contains the correct log counts."""
    summary_path = "/home/user/summary.txt"
    assert os.path.isfile(summary_path), f"The file {summary_path} was not generated. Did you run the script successfully?"

    with open(summary_path, "r") as f:
        content = f.read().strip()

    try:
        results = ast.literal_eval(content)
    except Exception as e:
        pytest.fail(f"Failed to parse the contents of {summary_path}. Expected a dictionary string. Error: {e}")

    expected_results = {'ERROR': 2, 'CRITICAL': 1}
    assert results == expected_results, f"The summary results are incorrect. Expected {expected_results}, got {results}."


def test_json_conflict_resolved():
    """Test that the conflicting local json.py module has been removed or renamed."""
    json_path = "/home/user/json.py"
    assert not os.path.isfile(json_path), f"The conflicting module {json_path} still exists. It must be removed or renamed to resolve the dependency conflict."


def test_log_aggregator_fixed():
    """Test that log_aggregator.py has been modified to properly decode the base64 config."""
    script_path = "/home/user/log_aggregator.py"
    assert os.path.isfile(script_path), f"Missing {script_path}"

    with open(script_path, "r") as f:
        content = f.read()

    assert "b64decode" in content, "The log_aggregator.py script does not appear to use base64 decoding for the config data."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
