#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import subprocess

def test_recovered_key():
    key_path = "/home/user/recovered_key.txt"
    assert os.path.isfile(key_path), f"File {key_path} does not exist. You must create it with the recovered API key."
    with open(key_path, "r") as f:
        content = f.read().strip()
    assert content == "sk-live-7x89asdf897asdf897897", "The recovered API key in recovered_key.txt is incorrect."

def test_package_installed():
    # Check if the package is installed via pip list
    result = subprocess.run(["pip", "list"], capture_output=True, text=True)
    assert "legacy-pipeline" in result.stdout or "legacy_pipeline" in result.stdout, "The legacy_pipeline package does not appear to be installed. Please fix the build error and run pip install -e /home/user/legacy_pipeline."

    # Check if the process_data executable is in PATH
    try:
        subprocess.run(["process_data"], capture_output=True, text=True)
    except FileNotFoundError:
        assert False, "The 'process_data' command is not available in PATH. The package might not be installed correctly."

def test_mre_json():
    mre_path = "/home/user/mre.json"
    assert os.path.isfile(mre_path), f"File {mre_path} does not exist. You must create it with the crashing JSON payload."
    with open(mre_path, "r") as f:
        content = f.read().strip()

    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        assert False, "mre.json does not contain valid JSON."

    expected = {"id": 742, "status": "active", "priority": -1, "test_flag": True, "value": "crash_me"}
    assert data == expected, f"The MRE JSON is incorrect. Expected {expected}, but got {data}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
