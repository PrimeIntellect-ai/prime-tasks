#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess

INCIDENT_DIR = "/home/user/incident"
ENV_FILE = os.path.join(INCIDENT_DIR, ".env")
SUCCESS_LOG = os.path.join(INCIDENT_DIR, "success.log")
VALIDATE_SCRIPT = os.path.join(INCIDENT_DIR, "validate.sh")
EXPECTED_TOKEN = "sec_k93jD82hf8z"
EXPECTED_SCRIPT = '''#!/bin/bash

source /home/user/incident/.env

if [ -z "$API_TOKEN" ]; then
    echo "Error: API_TOKEN not set"
    exit 1
fi

# Intermediate calculation
val1=10
val2=5
sum=$((val1 + val2))

# Intermediate validation assertion
if [ "$sum" -ne 15 ]; then
    echo "Assertion failed: sum is not 15"
    exit 1
fi

echo "Pipeline executed successfully with token $API_TOKEN" > /home/user/incident/success.log
'''

def test_env_file_exists_and_correct():
    assert os.path.isfile(ENV_FILE), f"The file {ENV_FILE} does not exist. Did you create it?"
    with open(ENV_FILE, "r") as f:
        content = f.read().strip()

    expected_line = f"API_TOKEN={EXPECTED_TOKEN}"
    assert expected_line in content, f"{ENV_FILE} does not contain the correct API_TOKEN line. Expected '{expected_line}'."
    assert content == expected_line, f"{ENV_FILE} must contain exactly '{expected_line}'."

def test_validate_script_is_fixed():
    assert os.path.isfile(VALIDATE_SCRIPT), f"The script {VALIDATE_SCRIPT} is missing."
    mode = os.lstat(VALIDATE_SCRIPT).st_mode
    assert stat.S_ISREG(mode), f"{VALIDATE_SCRIPT} must be a regular file, not a symlink or other file type."
    assert os.access(VALIDATE_SCRIPT, os.X_OK), f"The script {VALIDATE_SCRIPT} is not executable."

    with open(VALIDATE_SCRIPT, "r") as f:
        content = f.read()

    assert "val2=5" in content, "The script validate.sh was not correctly fixed. Expected 'val2=5'."
    assert "val2=0" not in content, "The script validate.sh still contains the bug 'val2=0'."
    assert content == EXPECTED_SCRIPT, "validate.sh does not match the correctly reverted working version."

def test_validate_script_executes_and_generates_log():
    if os.path.lexists(SUCCESS_LOG):
        os.unlink(SUCCESS_LOG)

    result = subprocess.run(
        [VALIDATE_SCRIPT],
        cwd=INCIDENT_DIR,
        env={"PATH": "/usr/bin:/bin"},
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"validate.sh failed with exit code {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )
    assert os.path.isfile(SUCCESS_LOG), "validate.sh did not generate success.log when executed."

def test_success_log_exists_and_correct():
    assert os.path.isfile(SUCCESS_LOG), f"The file {SUCCESS_LOG} does not exist. Did you run the script successfully?"
    with open(SUCCESS_LOG, "r") as f:
        content = f.read().strip()

    expected_msg = f"Pipeline executed successfully with token {EXPECTED_TOKEN}"
    assert content == expected_msg, f"The contents of {SUCCESS_LOG} are incorrect. Expected '{expected_msg}', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
