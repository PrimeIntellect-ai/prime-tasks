#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import pytest

SCRIPT = "/home/user/rebuild_config.py"
BUNDLE = "/home/user/net_bundle"
ORACLE = "/app/net_oracle"

def test_script_exists_and_is_python_file():
    assert os.path.isfile(SCRIPT), f"Required script missing at {SCRIPT}."
    with open(SCRIPT, "rb") as f:
        source = f.read()
    compile(source, SCRIPT, "exec")

def test_script_rebuilds_bundle_and_invokes_oracle():
    if os.path.lexists(BUNDLE):
        subprocess.run(["rm", "-rf", BUNDLE], check=True)

    try:
        result = subprocess.run(
            ["python3", SCRIPT], capture_output=True, text=True, timeout=30, check=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Script execution failed with return code {e.returncode}. stderr: {e.stderr}")
    except Exception as e:
        pytest.fail(f"Failed to execute rebuild script: {e}")

    assert os.path.isdir(BUNDLE), f"The directory {BUNDLE} was not created by the script."
    for name in ("authorized_keys", "fstab_snippet", "group_snippet"):
        assert os.path.isfile(os.path.join(BUNDLE, name)), f"Bundle file {name} is missing."

    parsed = None
    for line in result.stdout.splitlines():
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict) and "accuracy" in value:
            parsed = value
    assert parsed is not None, f"Script did not print the oracle's JSON output. stdout: {result.stdout!r}"
    assert float(parsed["accuracy"]) >= 0.95, f"Printed oracle accuracy is too low: {parsed}"

def test_net_bundle_directory_exists():
    assert os.path.isdir(BUNDLE), f"The directory {BUNDLE} does not exist. Did your script create it?"

def test_oracle_accuracy():
    assert os.path.exists(ORACLE), f"Oracle binary missing at {ORACLE}."
    assert os.path.isdir(BUNDLE), f"Bundle directory missing at {BUNDLE}."

    try:
        result = subprocess.run(
            [ORACLE, BUNDLE], capture_output=True, text=True, check=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Oracle binary execution failed with return code {e.returncode}. stderr: {e.stderr}")
    except Exception as e:
        pytest.fail(f"Failed to execute oracle binary: {e}")

    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"Failed to parse JSON output from oracle binary. Output was: {result.stdout}")

    assert "accuracy" in data, f"Oracle JSON output missing 'accuracy' key. Output: {data}"
    accuracy = float(data["accuracy"])
    threshold = 0.95
    assert accuracy >= threshold, (
        f"Accuracy metric too low. Expected accuracy >= {threshold}, but got {accuracy}. "
        "Ensure your authorized_keys, fstab_snippet, and group_snippet are correctly formatted and contain the right data."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
