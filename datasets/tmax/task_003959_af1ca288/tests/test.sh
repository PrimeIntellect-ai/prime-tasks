#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess
import sys


def test_deploy_keys_permissions():
    dir_path = "/home/user/deploy_keys"
    file_path = "/home/user/deploy_keys/id_ed25519"

    assert os.path.exists(dir_path), f"Directory {dir_path} does not exist."
    dir_stat = os.stat(dir_path)
    assert oct(stat.S_IMODE(dir_stat.st_mode)) == "0o700", f"Permissions for {dir_path} are not 700. Got {oct(stat.S_IMODE(dir_stat.st_mode))}."

    assert os.path.exists(file_path), f"File {file_path} does not exist."
    file_stat = os.stat(file_path)
    assert oct(stat.S_IMODE(file_stat.st_mode)) == "0o600", f"Permissions for {file_path} are not 600. Got {oct(stat.S_IMODE(file_stat.st_mode))}."


def test_failed_services_txt():
    file_path = "/home/user/failed_services.txt"
    assert os.path.exists(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = ["inventory-api", "payment-service", "user-profile"]
    assert lines == expected, f"Contents of {file_path} do not match the expected deduplicated and sorted list. Expected {expected}, got {lines}."


def test_ci_report_json():
    file_path = "/home/user/ci_report.json"
    assert os.path.exists(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {file_path} does not contain valid JSON."

    expected_services = ["inventory-api", "payment-service", "user-profile"]

    assert "pipeline_status" in data, f"'pipeline_status' key missing in {file_path}."
    assert data["pipeline_status"] == "failed", f"'pipeline_status' should be 'failed', got '{data['pipeline_status']}'."

    assert "failed_services" in data, f"'failed_services' key missing in {file_path}."
    assert data["failed_services"] == expected_services, f"'failed_services' list is incorrect. Expected {expected_services}, got {data['failed_services']}."


def test_build_report_script_exists():
    file_path = "/home/user/build_report.py"
    assert os.path.exists(file_path), f"Python script {file_path} does not exist. You must write the script to this location."
    assert stat.S_ISREG(os.stat(file_path).st_mode), f"Python script {file_path} is not a regular file."


def test_build_report_script_generates_report_from_input():
    script_path = "/home/user/build_report.py"
    services_path = "/home/user/failed_services.txt"
    report_path = "/home/user/ci_report.json"

    assert os.path.exists(script_path), f"Python script {script_path} does not exist."
    assert stat.S_ISREG(os.stat(script_path).st_mode), f"Python script {script_path} is not a regular file."

    original_services = open(services_path, "rb").read()
    original_report = open(report_path, "rb").read()
    token = secrets.token_hex(12)
    probe_services = [f"alpha-{token}", f"zeta-{token}"]

    try:
        with open(services_path, "w") as f:
            f.write("\n".join(probe_services) + "\n")
        os.remove(report_path)

        result = subprocess.run(
            [sys.executable, script_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"Executing {script_path} failed with exit code {result.returncode}. "
            f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
        )
        assert os.path.isfile(report_path), f"Executing {script_path} did not create {report_path}."

        with open(report_path, "r") as f:
            generated = json.load(f)
        expected = {
            "pipeline_status": "failed",
            "failed_services": probe_services,
        }
        assert generated == expected, f"Script output is incorrect for supplied input. Expected {expected}, got {generated}."
    finally:
        with open(services_path, "wb") as f:
            f.write(original_services)
        with open(report_path, "wb") as f:
            f.write(original_report)

    test_deploy_keys_permissions()
    test_failed_services_txt()
    test_ci_report_json()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
