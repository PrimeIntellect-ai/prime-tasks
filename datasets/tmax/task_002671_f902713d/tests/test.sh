#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import pytest

def test_timeline_exists_and_correct():
    timeline_path = "/home/user/timeline.txt"
    assert os.path.isfile(timeline_path), f"Timeline file {timeline_path} is missing."

    expected_lines = [
        "1698228000 service_a [INFO] Pipeline started",
        "1698228005 service_b [DEBUG] Loading configuration from config.env",
        "1698228008 service_b [WARN] Retrying connection",
        "1698228010 service_c [ERROR] Data sync failed: SYNC_TIMEOUT is not set or empty",
        "1698228015 service_a [INFO] Pipeline finished with errors"
    ]

    with open(timeline_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {timeline_path}, but found {len(actual_lines)}."

    for i, (expected, actual) in enumerate(zip(expected_lines, actual_lines)):
        assert actual == expected, f"Line {i+1} mismatch in {timeline_path}.\nExpected: {expected}\nActual: {actual}"

def test_run_sync_script_success():
    script_path = "/home/user/run_sync.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    try:
        result = subprocess.run(
            [script_path],
            capture_output=True,
            text=True,
            check=False
        )
    except Exception as e:
        pytest.fail(f"Failed to execute {script_path}: {e}")

    assert result.returncode == 0, f"Script {script_path} failed with exit code {result.returncode}.\nStderr: {result.stderr}"
    assert "SYNC SUCCESS" in result.stdout, f"Script {script_path} did not output 'SYNC SUCCESS'.\nStdout: {result.stdout}"

def test_config_misconfiguration_is_fixed():
    config_path = "/home/user/config.env"
    assert os.path.isfile(config_path), f"Config file {config_path} is missing."

    result = subprocess.run(
        [
            "/bin/bash", "--noprofile", "--norc", "-c",
            'unset SYNC_TIMEOUT SYNC_TIMOUT; source "$1" && '
            '[[ ${SYNC_TIMEOUT+x} == x ]] && [[ "$SYNC_TIMEOUT" == "30" ]] && '
            '[[ ${SYNC_TIMOUT+x} != x ]]',
            "_", config_path
        ],
        capture_output=True,
        text=True,
        check=False
    )

    assert result.returncode == 0, (
        "config.env must define SYNC_TIMEOUT=30 and must not define the misspelled "
        f"SYNC_TIMOUT variable.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
