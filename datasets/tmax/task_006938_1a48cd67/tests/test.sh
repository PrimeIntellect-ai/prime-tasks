#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def test_audit_report_exists():
    assert os.path.isfile("/home/user/audit_report.json"), "The file /home/user/audit_report.json does not exist."

def test_audit_report_structure():
    with open("/home/user/audit_report.json", "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file /home/user/audit_report.json is not valid JSON.")

    assert "scanned_files" in report, "The report is missing the 'scanned_files' key."
    assert "vulnerabilities" in report, "The report is missing the 'vulnerabilities' key."

    assert report["scanned_files"] == 3, f"Expected 3 scanned_files, but got {report['scanned_files']}."

    vulns = report["vulnerabilities"]
    assert isinstance(vulns, list), "The 'vulnerabilities' key must be a list."

    for v in vulns:
        assert "file" in v, f"Vulnerability entry missing 'file' key: {v}"
        assert "type" in v, f"Vulnerability entry missing 'type' key: {v}"
        assert "line_number" in v, f"Vulnerability entry missing 'line_number' key: {v}"

def test_audit_report_content():
    with open("/home/user/audit_report.json", "r") as f:
        report = json.load(f)

    vulns = report["vulnerabilities"]

    # Check sorting
    sorted_vulns = sorted(vulns, key=lambda x: (x["file"], x["line_number"]))
    assert vulns == sorted_vulns, "The vulnerabilities list is not sorted alphabetically by file name, then by line_number in ascending order."

    # Expected vulnerabilities based on the provided truth
    expected = [
        {"file": "/home/user/scripts/backup_service.py", "type": "credential_leakage", "line_number": 8},
        {"file": "/home/user/scripts/user_mgmt.py", "type": "command_injection", "line_number": 5},
        {"file": "/home/user/scripts/user_mgmt.py", "type": "credential_leakage", "line_number": 9},
        {"file": "/home/user/scripts/user_mgmt.py", "type": "command_injection", "line_number": 9}
    ]

    # Sort expected to match the required order
    expected_sorted = sorted(expected, key=lambda x: (x["file"], x["line_number"]))

    # Check lengths
    assert len(vulns) == len(expected_sorted), f"Expected {len(expected_sorted)} vulnerabilities, but found {len(vulns)}."

    for exp in expected_sorted:
        assert exp in vulns, f"Expected vulnerability not found in report: {exp}"
TEST_EOF

cat << 'TEST_EOF' > /tmp/test_dynamic_audit.py
import ast
import json
import os
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

TOOL = "/home/user/audit_tool.py"
REPORT = "/home/user/audit_report.json"


def call_lines(source, qualified_name):
    result = []
    for node in ast.walk(ast.parse(source)):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Attribute) and isinstance(func.value, ast.Name):
            name = f"{func.value.id}.{func.attr}"
            if name == qualified_name:
                result.append(node.lineno)
    return sorted(result)


def run_case(files, expected_builder):
    target = Path(tempfile.mkdtemp(prefix="audit-input-"))
    written = {}
    for name, source in files.items():
        path = target / name
        path.write_text(source, encoding="utf-8")
        written[name] = (str(path), source)
    (target / "ignored.txt").write_text("os.system(f'useradd {username}')\n", encoding="utf-8")

    if os.path.exists(REPORT):
        os.unlink(REPORT)
    result = subprocess.run(
        [sys.executable, TOOL, str(target)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"audit tool failed: stdout={result.stdout!r}, stderr={result.stderr!r}"
    assert os.path.isfile(REPORT), "The tool did not generate /home/user/audit_report.json"

    with open(REPORT, "r", encoding="utf-8") as handle:
        report = json.load(handle)
    assert "scanned_files" in report
    assert "vulnerabilities" in report
    assert report["scanned_files"] == len(files)
    assert isinstance(report["vulnerabilities"], list)

    vulnerabilities = report["vulnerabilities"]
    for entry in vulnerabilities:
        assert set(entry) == {"file", "type", "line_number"}
    assert vulnerabilities == sorted(vulnerabilities, key=lambda x: (x["file"], x["line_number"]))

    expected = expected_builder(written)
    canonical = lambda entries: sorted(entries, key=lambda x: (x["file"], x["line_number"], x["type"]))
    assert canonical(vulnerabilities) == canonical(expected)


def test_tool_exists_and_analyzes_unseen_directories():
    assert os.path.isfile(TOOL), "The required /home/user/audit_tool.py does not exist"

    suffix = uuid.uuid4().hex
    credential_source = '''import subprocess

def execute(token, host):
    subprocess.run(["client", "--token", token])
    subprocess.Popen("client --token=" + token, shell=True)
    subprocess.call(f"client --token {token}", shell=True)
    subprocess.run(["ping", host])
'''
    system_source = '''import os

def administer(username, password):
    os.system("useradd {}".format(username))
    os.system(f"set-password {password}")
    os.system("printf fixed")
'''
    safe_source = '''import subprocess

def check(host):
    subprocess.run(["ping", "-c", "1", host])
'''
    credential_name = f"credentials_{suffix}.py"
    system_name = f"commands_{suffix}.py"
    safe_name = f"safe_{suffix}.py"

    def expected(written):
        credential_path, credential_text = written[credential_name]
        system_path, system_text = written[system_name]
        subprocess_lines = (
            call_lines(credential_text, "subprocess.run")[:1]
            + call_lines(credential_text, "subprocess.Popen")
            + call_lines(credential_text, "subprocess.call")
        )
        os_lines = call_lines(system_text, "os.system")
        entries = [
            {"file": credential_path, "type": "credential_leakage", "line_number": line}
            for line in subprocess_lines
        ]
        entries.extend([
            {"file": system_path, "type": "command_injection", "line_number": os_lines[0]},
            {"file": system_path, "type": "credential_leakage", "line_number": os_lines[1]},
            {"file": system_path, "type": "command_injection", "line_number": os_lines[1]},
        ])
        return entries

    run_case(
        {
            credential_name: credential_source,
            system_name: system_source,
            safe_name: safe_source,
        },
        expected,
    )


def test_tool_uses_the_supplied_directory_on_another_input():
    suffix = uuid.uuid4().hex
    popen_source = '''import subprocess

def connect(secret):
    subprocess.Popen(["connector", "--secret", secret])
'''
    os_source = '''import os

def deploy(api_key):
    os.system(f"deploy --key {api_key}")
'''
    popen_name = f"runner_{suffix}.py"
    os_name = f"deploy_{suffix}.py"

    def expected(written):
        popen_path, popen_text = written[popen_name]
        os_path, os_text = written[os_name]
        popen_line = call_lines(popen_text, "subprocess.Popen")[0]
        os_line = call_lines(os_text, "os.system")[0]
        return [
            {"file": popen_path, "type": "credential_leakage", "line_number": popen_line},
            {"file": os_path, "type": "credential_leakage", "line_number": os_line},
            {"file": os_path, "type": "command_injection", "line_number": os_line},
        ]

    run_case({popen_name: popen_source, os_name: os_source}, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 && \
   python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_dynamic_audit.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
