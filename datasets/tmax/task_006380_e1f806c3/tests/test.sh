#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess
import time
import uuid

import jwt
import pytest

HOME = "/home/user"
SOURCE = os.path.join(HOME, "process_audit.go")
GO_MOD = os.path.join(HOME, "go.mod")
RAW_LOGS = os.path.join(HOME, "raw_logs.jsonl")
BLOCKLIST = os.path.join(HOME, "blocklist.txt")
AUDIT = os.path.join(HOME, "audit_trail.jsonl")
SERVER_CERT = os.path.join(HOME, "certs/server.crt")
SERVER_KEY = os.path.join(HOME, "certs/server.key")
ROGUE_KEY = os.path.join(HOME, "certs/rogue.key")
BINARY = "/tmp/process_audit_submission"


def clear_outputs():
    for path in (BLOCKLIST, AUDIT):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_program(check=True):
    result = subprocess.run(
        [BINARY], cwd=HOME, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=30
    )
    if check:
        assert result.returncode == 0, (
            f"process_audit.go exited with {result.returncode}. "
            f"stdout={result.stdout!r} stderr={result.stderr!r}"
        )
    return result


def test_blocklist_contents():
    blocklist_path = "/home/user/blocklist.txt"
    assert os.path.isfile(blocklist_path), f"File {blocklist_path} does not exist. The Go program failed to create it."

    with open(blocklist_path, 'r') as f:
        ips = [line.strip() for line in f if line.strip()]

    expected_ips = {"10.0.0.5", "172.16.0.8"}
    actual_ips = set(ips)

    assert actual_ips == expected_ips, f"Blocklist does not contain the expected IPs. Expected {expected_ips}, but found {actual_ips}."
    assert len(ips) == 2, f"Blocklist should contain exactly 2 IPs, but found {len(ips)}."


def test_audit_trail_contents():
    audit_path = "/home/user/audit_trail.jsonl"
    assert os.path.isfile(audit_path), f"File {audit_path} does not exist. The Go program failed to create it."

    with open(audit_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Audit trail should contain exactly 2 entries, but found {len(lines)}."

    expected_entries = [
        {"ip": "192.168.1.10", "endpoint": "/api/data", "token": "REDACTED"},
        {"ip": "192.168.1.11", "endpoint": "/api/users", "token": "REDACTED"}
    ]

    actual_entries = []
    for line in lines:
        try:
            entry = json.loads(line)
            actual_entries.append(entry)
        except json.JSONDecodeError:
            pytest.fail(f"Audit trail contains an invalid JSON line: {line}")

    for expected in expected_entries:
        assert expected in actual_entries, f"Expected entry {expected} was not found in the audit trail. Actual entries: {actual_entries}"


def assert_generated_outputs(expected_blocked, expected_audited):
    assert os.path.isfile(BLOCKLIST), "The executed Go program did not create blocklist.txt"
    with open(BLOCKLIST, "r") as f:
        blocked = [line.strip() for line in f if line.strip()]
    assert set(blocked) == set(expected_blocked), (
        f"Dynamic blocklist mismatch: expected {set(expected_blocked)}, found {set(blocked)}"
    )
    assert len(blocked) == len(expected_blocked), "Dynamic blocklist contains duplicates or extra lines"

    assert os.path.isfile(AUDIT), "The executed Go program did not create audit_trail.jsonl"
    with open(AUDIT, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == len(expected_audited), (
        f"Dynamic audit trail should contain {len(expected_audited)} entries, found {len(lines)}"
    )
    entries = []
    for line in lines:
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            pytest.fail(f"Dynamic audit trail contains invalid JSON: {line}")
    for expected in expected_audited:
        assert expected in entries, f"Expected dynamic audit entry {expected} was not found in {entries}"


def test_submission_end_to_end():
    assert os.path.exists(SOURCE), "/home/user/process_audit.go does not exist"
    assert not os.path.islink(SOURCE), "process_audit.go must be a regular Go source file"
    assert stat.S_ISREG(os.stat(SOURCE).st_mode), "process_audit.go is not a regular file"
    assert os.path.isfile(GO_MOD), "The required Go module was not initialized in /home/user"

    with open(SOURCE, "r", encoding="utf-8") as f:
        source_text = f.read()
    assert "crypto/x509" in source_text, "The Go program does not use crypto/x509"
    assert "github.com/golang-jwt/jwt/v5" in source_text, "The Go program does not use the required JWT v5 module"

    build = subprocess.run(
        ["go", "build", "-o", BINARY, SOURCE], cwd=HOME, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
    )
    assert build.returncode == 0, f"process_audit.go did not build: {build.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "Go build did not produce an executable"

    with open(RAW_LOGS, "rb") as f:
        original_logs = f.read()
    with open(SERVER_CERT, "rb") as f:
        original_cert = f.read()

    try:
        # Execute the submitted artifact on the supplied data, then retain all
        # assertions from the original verifier.
        clear_outputs()
        run_program()
        test_blocklist_contents()
        test_audit_trail_contents()

        with open(SERVER_KEY, "r") as f:
            server_key = f.read()
        with open(ROGUE_KEY, "r") as f:
            rogue_key = f.read()

        now = int(time.time())
        probe_ip = f"198.51.100.{secrets.randbelow(200) + 1}"
        probe_endpoint = "/cert-probe/" + uuid.uuid4().hex
        probe_token = jwt.encode({"sub": uuid.uuid4().hex, "exp": now + 1800}, server_key, algorithm="RS256")
        with open(RAW_LOGS, "w") as f:
            f.write(json.dumps({"ip": probe_ip, "endpoint": probe_endpoint, "token": probe_token}) + "\n")

        # Use a self-signed certificate carrying the same public key. JWT-only
        # checking would still succeed, so accepting this entry demonstrates
        # that the certificate chain was not verified against ca.crt.
        invalid_cert = "/tmp/self_signed_server.crt"
        cert_result = subprocess.run(
            ["openssl", "req", "-x509", "-new", "-key", SERVER_KEY,
             "-out", invalid_cert, "-days", "1", "-subj", "/CN=Untrusted Server"],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert cert_result.returncode == 0, cert_result.stderr
        with open(invalid_cert, "rb") as src, open(SERVER_CERT, "wb") as dst:
            dst.write(src.read())
        clear_outputs()
        run_program(check=False)
        invalid_cert_entries = []
        if os.path.isfile(AUDIT):
            with open(AUDIT, "r") as f:
                for line in f:
                    try:
                        invalid_cert_entries.append(json.loads(line))
                    except json.JSONDecodeError:
                        pass
        forbidden = {"ip": probe_ip, "endpoint": probe_endpoint, "token": "REDACTED"}
        assert forbidden not in invalid_cert_entries, (
            "The program processed a valid JWT while server.crt was not signed by ca.crt"
        )

        with open(SERVER_CERT, "wb") as f:
            f.write(original_cert)

        valid_records = []
        invalid_records = []
        for index in range(3):
            ip = f"203.0.113.{secrets.randbelow(200) + 1}"
            endpoint = f"/dynamic/valid/{uuid.uuid4().hex}"
            token = jwt.encode({"sub": uuid.uuid4().hex, "exp": now + 1800 + index}, server_key, algorithm="RS256")
            valid_records.append({"ip": ip, "endpoint": endpoint, "token": token})

        invalid_records.append({
            "ip": f"198.51.100.{secrets.randbelow(200) + 1}",
            "endpoint": "/dynamic/bad-signature/" + uuid.uuid4().hex,
            "token": jwt.encode({"sub": uuid.uuid4().hex, "exp": now + 1800}, rogue_key, algorithm="RS256")
        })
        invalid_records.append({
            "ip": f"192.0.2.{secrets.randbelow(200) + 1}",
            "endpoint": "/dynamic/expired/" + uuid.uuid4().hex,
            "token": jwt.encode({"sub": uuid.uuid4().hex, "exp": now - 3600}, server_key, algorithm="RS256")
        })
        invalid_records.append({
            "ip": f"100.64.{secrets.randbelow(200)}.{secrets.randbelow(200) + 1}",
            "endpoint": "/dynamic/malformed/" + uuid.uuid4().hex,
            "token": "not-a-jwt-" + uuid.uuid4().hex
        })

        records = [valid_records[0], invalid_records[0], valid_records[1], invalid_records[1], invalid_records[2], valid_records[2]]
        with open(RAW_LOGS, "w") as f:
            for record in records:
                f.write(json.dumps(record) + "\n")

        clear_outputs()
        run_program()
        expected_audited = [
            {"ip": record["ip"], "endpoint": record["endpoint"], "token": "REDACTED"}
            for record in valid_records
        ]
        expected_blocked = [record["ip"] for record in invalid_records]
        assert_generated_outputs(expected_blocked, expected_audited)
    finally:
        with open(RAW_LOGS, "wb") as f:
            f.write(original_logs)
        with open(SERVER_CERT, "wb") as f:
            f.write(original_cert)
        clear_outputs()
        if os.path.isfile(BINARY):
            try:
                run_program(check=False)
            except Exception:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
