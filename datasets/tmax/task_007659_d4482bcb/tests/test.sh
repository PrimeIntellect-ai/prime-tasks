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

SCRIPT = "/home/user/analyze.py"
REPORT = "/home/user/report.json"
APP = "/home/user/vulnerable_app.py"
LOG = "/home/user/access.log"
EVIDENCE = "/home/user/evidence"


def run_analyzer():
    if os.path.exists(REPORT):
        os.remove(REPORT)
    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"analyze.py exited with status {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )
    assert os.path.isfile(REPORT), "Executing analyze.py did not create /home/user/report.json."


def load_report():
    try:
        with open(REPORT, "r") as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {REPORT} does not contain valid JSON.")
    except Exception as e:
        pytest.fail(f"Failed to read {REPORT}: {e}")


def test_00_execute_analyzer():
    assert os.path.isfile(SCRIPT), f"The script {SCRIPT} does not exist."
    run_analyzer()


def test_analyze_script_exists():
    path = "/home/user/analyze.py"
    assert os.path.isfile(path), f"The script {path} does not exist."


def test_report_exists():
    path = "/home/user/report.json"
    assert os.path.isfile(path), f"The report file {path} does not exist. Ensure your script creates it."


def test_report_content():
    path = "/home/user/report.json"

    if not os.path.isfile(path):
        pytest.fail(f"Cannot test content because {path} is missing.")

    try:
        with open(path, "r") as f:
            report_data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {path} does not contain valid JSON.")
    except Exception as e:
        pytest.fail(f"Failed to read {path}: {e}")

    # Expected values based on the setup
    expected_cwe = "CWE-78"
    expected_ip = "172.16.22.109"
    expected_file = "persistence_bind.sh"

    # Validate CWE
    assert "cwe" in report_data, "The JSON report is missing the 'cwe' key."
    assert report_data["cwe"] == expected_cwe, f"Incorrect CWE. Expected '{expected_cwe}', got '{report_data['cwe']}'."

    # Validate Attacker IP
    assert "attacker_ip" in report_data, "The JSON report is missing the 'attacker_ip' key."
    assert report_data["attacker_ip"] == expected_ip, f"Incorrect attacker IP. Expected '{expected_ip}', got '{report_data['attacker_ip']}'."

    # Validate World Writable File
    assert "world_writable_file" in report_data, "The JSON report is missing the 'world_writable_file' key."
    assert report_data["world_writable_file"] == expected_file, f"Incorrect world writable file. Expected '{expected_file}', got '{report_data['world_writable_file']}'."


def test_analyzer_uses_current_evidence_and_logs():
    token = uuid.uuid4().hex[:10]
    expected_ip = f"198.51.100.{int(token[:2], 16) % 200 + 1}"
    expected_file = f"implant_{token}.sh"
    original_world_writable = os.path.join(EVIDENCE, "persistence_bind.sh")
    changed_world_writable = os.path.join(EVIDENCE, expected_file)

    with open(APP, "rb") as f:
        original_app = f.read()
    with open(LOG, "rb") as f:
        original_log = f.read()
    original_report = None
    if os.path.isfile(REPORT):
        with open(REPORT, "rb") as f:
            original_report = f.read()

    try:
        # Same command-injection vulnerability, but without the answer-bearing
        # comment and with a different vulnerable parameter name.
        variant_app = '''from flask import Flask, request
import os

app = Flask(__name__)

@app.route('/check')
def check():
    target = request.args.get('target', '127.0.0.1')
    output = os.popen(f"ping -c 1 {target}").read()
    return output
'''
        with open(APP, "w") as f:
            f.write(variant_app)

        variant_log = f'''203.0.113.10 - - [24/Oct/2023:10:15:32 +0000] "GET / HTTP/1.1" 200 45 "-" "Mozilla/5.0"
203.0.113.11 - - [24/Oct/2023:10:16:01 +0000] "GET /check?target=8.8.8.8 HTTP/1.1" 200 302 "-" "curl/7.68.0"
{expected_ip} - - [24/Oct/2023:13:44:55 +0000] "GET /check?target=127.0.0.1;id HTTP/1.1" 200 1024 "-" "python-requests/2.25.1"
'''
        with open(LOG, "w") as f:
            f.write(variant_log)

        os.rename(original_world_writable, changed_world_writable)
        os.chmod(changed_world_writable, 0o777)

        run_analyzer()
        report_data = load_report()
        assert report_data.get("cwe") == "CWE-78", (
            f"Incorrect CWE for the command-injection source: {report_data.get('cwe')!r}."
        )
        assert report_data.get("attacker_ip") == expected_ip, (
            "analyze.py did not derive the attacker IP from the current access log."
        )
        assert report_data.get("world_writable_file") == expected_file, (
            "analyze.py did not derive the world-writable base filename from the current evidence directory."
        )
    finally:
        with open(APP, "wb") as f:
            f.write(original_app)
        with open(LOG, "wb") as f:
            f.write(original_log)
        if os.path.exists(changed_world_writable):
            os.rename(changed_world_writable, original_world_writable)
        if os.path.exists(original_world_writable):
            os.chmod(original_world_writable, 0o777)
        if original_report is None:
            if os.path.exists(REPORT):
                os.remove(REPORT)
        else:
            with open(REPORT, "wb") as f:
                f.write(original_report)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
