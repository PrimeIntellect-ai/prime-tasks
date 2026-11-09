#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
import uuid

import pytest

PROBE_TOKEN_1 = "verifier-log-probe-" + uuid.uuid4().hex
PROBE_TOKEN_2 = "verifier-second-probe-" + uuid.uuid4().hex


@pytest.fixture(scope="session", autouse=True)
def run_submitted_collector():
    script_path = "/home/user/diag-tool/collect.sh"
    assert os.path.exists(script_path), "collect.sh is missing."
    mode = os.lstat(script_path).st_mode
    assert stat.S_ISREG(mode), "collect.sh must be a regular file."
    assert os.access(script_path, os.X_OK), "collect.sh is not executable."

    # Add unpredictable inputs after the agent has finished. A collector that
    # merely writes the known fixture strings cannot satisfy these checks.
    with open("/home/user/logs/verifier probe with spaces.log", "w") as f:
        f.write(PROBE_TOKEN_1 + "\n")
    with open("/home/user/logs/another verifier probe file.log", "w") as f:
        f.write(PROBE_TOKEN_2 + "\n")

    for output in ("/home/user/diag-tool/combined.log", "/home/user/report.json"):
        try:
            os.remove(output)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [script_path],
        cwd="/home/user/diag-tool",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        "collect.sh did not run successfully.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def test_report_json_exists_and_correct():
    report_path = "/home/user/report.json"
    assert os.path.exists(report_path), "report.json does not exist. The script might not have run successfully."

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "report.json does not contain valid JSON."

    assert data.get("status") == "success", f"Expected status 'success', got '{data.get('status')}'."
    assert data.get("secret") == "DIAG-SEC-77bbx9", f"Incorrect secret recovered. Got '{data.get('secret')}'."

    port = data.get("port")
    assert port == 8088 or port == "8088", f"Incorrect port extracted from pcap. Got '{port}'."


def test_combined_log_contains_all_entries():
    combined_log_path = "/home/user/diag-tool/combined.log"
    assert os.path.exists(combined_log_path), "combined.log was not generated. The script might have failed."

    with open(combined_log_path, "r") as f:
        content = f.read()

    assert "ERROR 55: Critical failure in processing" in content, (
        "The combined.log does not contain the error message from 'error log 1.txt'. "
        "The bash script loop was likely not fixed correctly to handle spaces in filenames."
    )
    assert "System initialized" in content, "The combined.log does not contain the entry from 'system log.txt'."
    assert "Normal log entry" in content, "The combined.log does not contain the entry from 'app_log.txt'."


def test_combined_log_contains_unpredictable_space_named_inputs():
    combined_log_path = "/home/user/diag-tool/combined.log"
    with open(combined_log_path, "r") as f:
        content = f.read()

    assert PROBE_TOKEN_1 in content, "collect.sh did not collect a newly added log whose filename contains spaces."
    assert PROBE_TOKEN_2 in content, "collect.sh did not collect the second newly added space-named log."


def test_env_file_updated():
    env_path = "/home/user/diag-tool/.env"
    assert os.path.exists(env_path), ".env file is missing."

    with open(env_path, "r") as f:
        content = f.read()

    assert "SECRET=DIAG-SEC-77bbx9" in content, "The .env file does not contain the correct recovered SECRET."
    assert "PORT=8088" in content, "The .env file does not contain the correct extracted PORT."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
