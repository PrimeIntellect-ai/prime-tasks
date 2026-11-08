#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import copy
import json
import os
import py_compile
import secrets
import subprocess
import sys
import pytest
from collections import Counter

TRAFFIC_FILE = "/home/user/traffic.json"
AUDIT_SCRIPT = "/home/user/audit.py"
AUDIT_RESULTS = "/home/user/audit_results.json"
BLOCK_IP_SCRIPT = "/home/user/block_ip.sh"
SSHD_CONFIG = "/home/user/sshd_config"


def get_expected_audit_and_ip():
    assert os.path.isfile(TRAFFIC_FILE), f"Original traffic file {TRAFFIC_FILE} is missing."
    with open(TRAFFIC_FILE, "r") as f:
        data = json.load(f)

    expected_results = []
    ip_counter = Counter()

    for req in data:
        headers = req.get("headers", {})
        cookie = headers.get("Cookie", "")
        if "admin_session" in cookie:
            ip_counter[req.get("source_ip")] += 1

            redacted_req = {
                "source_ip": req.get("source_ip"),
                "headers": dict(headers),
            }
            if "Authorization" in redacted_req["headers"]:
                redacted_req["headers"]["Authorization"] = "[REDACTED]"

            expected_results.append(redacted_req)

    if ip_counter:
        most_common_ip = ip_counter.most_common(1)[0][0]
    else:
        most_common_ip = None

    return expected_results, most_common_ip


def run_audit():
    subprocess.run(
        [sys.executable, AUDIT_SCRIPT],
        check=True,
        timeout=10,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def test_audit_results():
    assert os.path.isfile(AUDIT_RESULTS), f"Output file {AUDIT_RESULTS} does not exist."
    assert os.path.isfile(AUDIT_SCRIPT), f"Audit script {AUDIT_SCRIPT} does not exist."

    try:
        py_compile.compile(AUDIT_SCRIPT, doraise=True)
    except py_compile.PyCompileError as exc:
        pytest.fail(f"Audit script {AUDIT_SCRIPT} is not valid Python: {exc}")

    with open(TRAFFIC_FILE, "rb") as f:
        original_traffic = f.read()

    token = secrets.token_hex(12)
    probe_data = [
        {
            "source_ip": f"198.51.100.{secrets.randbelow(200) + 1}",
            "method": "GET",
            "headers": {
                "Host": f"{token}.example",
                "Cookie": f"theme=dark; admin_session={token}",
                "Authorization": f"Bearer {secrets.token_hex(18)}",
                "X-Probe": token,
            },
        },
        {
            "source_ip": f"203.0.113.{secrets.randbelow(200) + 1}",
            "method": "POST",
            "headers": {
                "Cookie": f"admin_session={secrets.token_hex(10)}",
                "User-Agent": f"probe-{token}",
            },
        },
        {
            "source_ip": f"192.0.2.{secrets.randbelow(200) + 1}",
            "headers": {
                "Cookie": f"ordinary_session={token}",
                "Authorization": f"Bearer {secrets.token_hex(18)}",
            },
        },
    ]
    expected_probe = []
    for request in probe_data:
        if "admin_session" in request.get("headers", {}).get("Cookie", ""):
            redacted = copy.deepcopy(request)
            if "Authorization" in redacted["headers"]:
                redacted["headers"]["Authorization"] = "[REDACTED]"
            expected_probe.append(redacted)

    try:
        with open(TRAFFIC_FILE, "w") as f:
            json.dump(probe_data, f)
        run_audit()
        with open(AUDIT_RESULTS, "r") as f:
            try:
                actual_probe = json.load(f)
            except json.JSONDecodeError:
                pytest.fail(f"File {AUDIT_RESULTS} is not valid JSON after executing {AUDIT_SCRIPT}.")
        assert actual_probe == expected_probe, (
            f"Executing {AUDIT_SCRIPT} did not correctly filter and redact a probe traffic log."
        )
    finally:
        with open(TRAFFIC_FILE, "wb") as f:
            f.write(original_traffic)

    expected_results, _ = get_expected_audit_and_ip()
    run_audit()

    with open(AUDIT_RESULTS, "r") as f:
        try:
            actual_results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {AUDIT_RESULTS} is not valid JSON.")

    assert actual_results == expected_results, (
        f"The contents of {AUDIT_RESULTS} do not match the expected filtered and redacted output."
    )


def test_audit_script_executable():
    assert os.path.isfile(AUDIT_SCRIPT), f"Audit script {AUDIT_SCRIPT} does not exist."
    assert os.access(AUDIT_SCRIPT, os.X_OK), f"Audit script {AUDIT_SCRIPT} is not executable."


def test_block_ip_script():
    assert os.path.isfile(BLOCK_IP_SCRIPT), f"Block IP script {BLOCK_IP_SCRIPT} does not exist."
    assert os.access(BLOCK_IP_SCRIPT, os.X_OK), f"Block IP script {BLOCK_IP_SCRIPT} is not executable."

    _, expected_ip = get_expected_audit_and_ip()
    assert expected_ip is not None, "Could not determine the target IP from the traffic log."

    expected_command = f"iptables -A INPUT -s {expected_ip} -j DROP"

    with open(BLOCK_IP_SCRIPT, "r") as f:
        content = f.read().strip()

    assert expected_command in content, (
        f"The script {BLOCK_IP_SCRIPT} does not contain the expected iptables command: "
        f"'{expected_command}'."
    )

    active_lines = []
    for line in content.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#!") or stripped.startswith("#"):
            continue
        command_text = stripped.split("#", 1)[0].strip()
        if command_text:
            active_lines.append(command_text)

    assert active_lines == [expected_command], (
        f"The script {BLOCK_IP_SCRIPT} must contain exactly one active command, exactly: "
        f"'{expected_command}'."
    )


def test_sshd_config_hardened():
    assert os.path.isfile(SSHD_CONFIG), f"SSH config file {SSHD_CONFIG} does not exist."

    with open(SSHD_CONFIG, "r") as f:
        lines = f.readlines()

    permit_root_login = False
    password_auth = False
    active_settings = {
        "permitrootlogin": [],
        "passwordauthentication": [],
    }

    for line in lines:
        stripped = line.strip()
        if stripped == "PermitRootLogin no":
            permit_root_login = True
        elif stripped == "PasswordAuthentication no":
            password_auth = True

        if not stripped or stripped.startswith("#"):
            continue
        directive_text = stripped.split("#", 1)[0].strip()
        parts = directive_text.split()
        if parts and parts[0].lower() in active_settings:
            active_settings[parts[0].lower()].append(parts)

    assert permit_root_login, (
        f"The setting 'PermitRootLogin no' was not found as an active configuration in {SSHD_CONFIG}."
    )
    assert password_auth, (
        f"The setting 'PasswordAuthentication no' was not found as an active configuration in {SSHD_CONFIG}."
    )

    for directive, records in active_settings.items():
        assert records, f"No active {directive} directive was found in {SSHD_CONFIG}."
        assert all(len(parts) == 2 and parts[1].lower() == "no" for parts in records), (
            f"Conflicting or invalid active {directive} directives remain in {SSHD_CONFIG}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
