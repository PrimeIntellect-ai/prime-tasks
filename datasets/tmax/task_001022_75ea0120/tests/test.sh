#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import re
import subprocess
import pytest

def test_repro_payload_json():
    path = "/home/user/incident_triage/repro_payload.json"
    assert os.path.isfile(path), f"File {path} does not exist. You must save the exact JSON payload."

    with open(path, "r") as f:
        try:
            payload = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} does not contain valid JSON.")

    expected = {
        "job_id": 1003, 
        "data": "gamma", 
        "send_email": True, 
        "user_email": "admin@example.com"
    }
    assert payload == expected, f"Extracted payload does not match the expected failing payload. Found: {payload}"

def test_venv_dependencies():
    python_bin = "/home/user/triage_venv/bin/python"
    assert os.path.exists(python_bin), "Virtual environment python executable not found at /home/user/triage_venv/bin/python"

    # Check Jinja2 version
    result = subprocess.run([python_bin, "-c", "import jinja2; print(jinja2.__version__)"], capture_output=True, text=True)
    assert result.returncode == 0, f"Jinja2 is not installed in the venv. Error: {result.stderr}"
    assert result.stdout.strip() == "2.11.3", f"Jinja2 MUST remain at version 2.11.3. Found: {result.stdout.strip()}"

    # Check MarkupSafe version
    result = subprocess.run([python_bin, "-c", "import markupsafe; print(markupsafe.__version__)"], capture_output=True, text=True)
    assert result.returncode == 0, f"MarkupSafe is not installed in the venv. Error: {result.stderr}"

    version_str = result.stdout.strip()
    try:
        parts = tuple(map(int, version_str.split('.')[:2]))
    except ValueError:
        pytest.fail(f"Could not parse MarkupSafe version: {version_str}")

    assert parts < (2, 1), f"MarkupSafe version must be < 2.1.0 to resolve the soft_unicode issue with Jinja2 2.11.3. Found {version_str}"

def test_resolution_txt():
    path = "/home/user/incident_triage/resolution.txt"
    assert os.path.isfile(path), f"File {path} does not exist. You must create a report."

    with open(path, "r") as f:
        content = f.read()

    assert "markupsafe" in content.lower(), "resolution.txt must mention the downgraded dependency (MarkupSafe)."

    match = re.search(r'markupsafe\s*(==|<=|<)?\s*(\d+\.\d+(?:\.\d+)?)', content, re.IGNORECASE)
    assert match is not None, "Could not find a version pin for MarkupSafe in resolution.txt (e.g., MarkupSafe==2.0.1)"

    version = match.group(2)
    parts = tuple(map(int, version.split('.')[:2]))
    assert parts < (2, 1), f"resolution.txt mentions MarkupSafe version {version}, which is not < 2.1.0 and will not fix the crash."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
