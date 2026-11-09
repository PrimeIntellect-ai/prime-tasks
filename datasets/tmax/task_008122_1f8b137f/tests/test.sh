#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import secrets
import subprocess

import pytest

REPORT_FILE = "/home/user/audit_report.json"
AUDIT_GO = "/home/user/audit.go"
ACCESS_LOG = "/home/user/service/access.log"
SERVER_SOURCE = "/home/user/service/server.go"
SERVER_BIN_PATH = "/home/user/service/server"


def run_auditor():
    if os.path.exists(REPORT_FILE):
        os.remove(REPORT_FILE)

    try:
        result = subprocess.run(
            ["go", "run", AUDIT_GO],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=90,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The Go auditor did not finish within 90 seconds.")

    assert result.returncode == 0, (
        "go run /home/user/audit.go failed.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT_FILE), (
        f"Executing {AUDIT_GO} did not generate {REPORT_FILE}"
    )


def load_report():
    with open(REPORT_FILE, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_FILE} does not contain valid JSON.")


def derive_expected_values():
    successful_xss_ips = []
    with open(ACCESS_LOG, "r") as f:
        for line in f:
            match = re.match(r"^(\S+).*\"\S+\s+\S*<script>\S*\s+HTTP/[^\"]+\"\s+(\d{3})\b", line)
            if match and 200 <= int(match.group(2)) < 300:
                successful_xss_ips.append(match.group(1))
    assert len(successful_xss_ips) == 1, "Verifier fixture must contain one successful XSS request"

    with open(SERVER_SOURCE, "r") as f:
        source = f.read()
    port_match = re.search(r"http\.ListenAndServe\s*\(\s*\"\:(\d+)\"", source)
    assert port_match, "Verifier fixture must contain an http.ListenAndServe port"

    with open(SERVER_BIN_PATH, "rb") as f:
        binary_hash = hashlib.sha256(f.read()).hexdigest()

    return successful_xss_ips[0], int(port_match.group(1)), binary_hash


def test_audit_report_exists_and_valid():
    assert os.path.isfile(AUDIT_GO), f"The Go auditor was not found at {AUDIT_GO}"
    assert os.path.getsize(AUDIT_GO) > 0, f"The Go auditor at {AUDIT_GO} is empty"

    # Compiles and executes the submitted Go artifact, requiring it to create a fresh report.
    run_auditor()

    assert os.path.isfile(REPORT_FILE), f"The audit report was not found at {REPORT_FILE}"

    data = load_report()

    assert "attacker_ip" in data, "Missing 'attacker_ip' key in the JSON report."
    assert "listening_port" in data, "Missing 'listening_port' key in the JSON report."
    assert "binary_sha256" in data, "Missing 'binary_sha256' key in the JSON report."

    assert data["attacker_ip"] == "10.55.20.13", f"Expected attacker_ip to be '10.55.20.13', got '{data['attacker_ip']}'"

    assert isinstance(data["listening_port"], int), f"Expected listening_port to be an integer, got {type(data['listening_port']).__name__}"
    assert data["listening_port"] == 8443, f"Expected listening_port to be 8443, got {data['listening_port']}"

    # Compute expected sha256 dynamically
    assert os.path.isfile(SERVER_BIN_PATH), f"The server binary was not found at {SERVER_BIN_PATH}"
    with open(SERVER_BIN_PATH, "rb") as f:
        bin_data = f.read()
    expected_hash = hashlib.sha256(bin_data).hexdigest()

    assert data["binary_sha256"] == expected_hash, f"Expected binary_sha256 to be '{expected_hash}', got '{data['binary_sha256']}'"


def test_auditor_parses_changed_inputs():
    with open(ACCESS_LOG, "rb") as f:
        original_log = f.read()
    with open(SERVER_SOURCE, "rb") as f:
        original_source = f.read()
    with open(SERVER_BIN_PATH, "rb") as f:
        original_binary = f.read()

    while True:
        attacker_ip = f"10.{secrets.randbelow(254) + 1}.{secrets.randbelow(254) + 1}.{secrets.randbelow(254) + 1}"
        if attacker_ip != "10.55.20.13":
            break
    while True:
        port = secrets.randbelow(40000) + 20000
        if port != 8443:
            break

    test_log = (
        '192.168.50.10 - - [01/Jan/2026:00:00:00 +0000] "GET /health HTTP/1.1" 200 2\n'
        f'{attacker_ip} - - [01/Jan/2026:00:00:01 +0000] "GET /search?q=<script>alert(1)</script> HTTP/1.1" 200 10\n'
        '192.168.50.11 - - [01/Jan/2026:00:00:02 +0000] "GET /about HTTP/1.1" 200 20\n'
    )
    test_source = f'''package main

import "net/http"

func main() {{
    http.ListenAndServe(":{port}", nil)
}}
'''
    test_binary = secrets.token_bytes(257)

    try:
        with open(ACCESS_LOG, "w") as f:
            f.write(test_log)
        with open(SERVER_SOURCE, "w") as f:
            f.write(test_source)
        with open(SERVER_BIN_PATH, "wb") as f:
            f.write(test_binary)

        expected_ip, expected_port, expected_hash = derive_expected_values()
        run_auditor()
        data = load_report()

        assert data.get("attacker_ip") == expected_ip
        assert isinstance(data.get("listening_port"), int)
        assert data.get("listening_port") == expected_port
        assert data.get("binary_sha256") == expected_hash
    finally:
        with open(ACCESS_LOG, "wb") as f:
            f.write(original_log)
        with open(SERVER_SOURCE, "wb") as f:
            f.write(original_source)
        with open(SERVER_BIN_PATH, "wb") as f:
            f.write(original_binary)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
