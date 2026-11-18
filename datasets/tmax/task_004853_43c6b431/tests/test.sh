#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import hashlib
import ipaddress
import pytest

REPORT_PATH = "/home/user/audit_report.json"
DATA_DIR = "/home/user/sec_data"

def compute_expected_integrity():
    manifest_path = os.path.join(DATA_DIR, "manifest.sha256")
    expected = {}
    if not os.path.isfile(manifest_path):
        return expected
    manifest_hashes = {}
    with open(manifest_path, "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 2:
                manifest_hashes[parts[1]] = parts[0]
    for filename in ["auth_logs.json", "network_policy.json", "connections.csv"]:
        filepath = os.path.join(DATA_DIR, filename)
        if not os.path.isfile(filepath):
            continue
        with open(filepath, "rb") as f:
            file_hash = hashlib.sha256(f.read()).hexdigest()
        expected[filename] = "PASS" if manifest_hashes.get(filename) == file_hash else "FAIL"
    return expected

def compute_expected_auth_violations():
    logs_path = os.path.join(DATA_DIR, "auth_logs.json")
    violations = []
    if not os.path.isfile(logs_path):
        return violations
    with open(logs_path, "r") as f:
        logs = json.load(f)
    for entry in logs:
        violation = False
        req_headers = entry.get("request", {}).get("headers", {})
        res_headers = entry.get("response", {}).get("headers", {})
        auth_header = req_headers.get("Authorization")
        if auth_header and not auth_header.startswith("Bearer "):
            violation = True
        set_cookie = res_headers.get("Set-Cookie")
        if set_cookie:
            parts = [p.strip() for p in set_cookie.split(";")]
            if "Secure" not in parts or "HttpOnly" not in parts:
                violation = True
        if violation:
            violations.append(entry["id"])
    return sorted(violations)

def compute_expected_connections():
    policy_path = os.path.join(DATA_DIR, "network_policy.json")
    conn_path = os.path.join(DATA_DIR, "connections.csv")
    evaluations = {}
    if not os.path.isfile(policy_path) or not os.path.isfile(conn_path):
        return evaluations
    with open(policy_path, "r") as f:
        policies = json.load(f)
    with open(conn_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            src_ip = ipaddress.ip_address(row["src_ip"])
            dest_port = int(row["dest_port"])
            allowed = any(
                src_ip in ipaddress.ip_network(rule["src_ip_range"])
                and dest_port == int(rule["dest_port"])
                for rule in policies
            )
            evaluations[row["conn_id"]] = "ALLOWED" if allowed else "DENIED"
    return evaluations

@pytest.fixture(scope="module")
def audit_report():
    assert os.path.isfile(REPORT_PATH), f"Output file {REPORT_PATH} was not created."
    with open(REPORT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT_PATH} is not a valid JSON file.")

def test_integrity_checks(audit_report):
    assert "integrity_checks" in audit_report, "Missing 'integrity_checks' key in report."
    expected = compute_expected_integrity()
    actual = audit_report["integrity_checks"]
    for filename, status in expected.items():
        assert filename in actual, f"Missing integrity check for {filename}"
        assert actual[filename] == status, f"Integrity check for {filename} should be {status}, got {actual[filename]}"

def test_auth_violations(audit_report):
    assert "auth_violations" in audit_report, "Missing 'auth_violations' key in report."
    expected = compute_expected_auth_violations()
    actual = sorted(audit_report["auth_violations"])
    assert actual == expected, f"Auth violations mismatch. Expected {expected}, got {actual}"

def test_connection_evaluations(audit_report):
    assert "connection_evaluations" in audit_report, "Missing 'connection_evaluations' key in report."
    expected = compute_expected_connections()
    actual = audit_report["connection_evaluations"]
    for conn_id, status in expected.items():
        assert conn_id in actual, f"Missing connection evaluation for {conn_id}"
        assert actual[conn_id] == status, f"Connection evaluation for {conn_id} should be {status}, got {actual[conn_id]}"
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_audit.py
import csv
import hashlib
import ipaddress
import json
import secrets
import subprocess
import sys
from pathlib import Path

SCRIPT = Path("/home/user/audit.py")
REPORT = Path("/home/user/audit_report.json")
DATA = Path("/home/user/sec_data")
FILES = ["auth_logs.json", "network_policy.json", "connections.csv", "manifest.sha256"]

original = {name: (DATA / name).read_bytes() for name in FILES}
original_report = REPORT.read_bytes() if REPORT.is_file() else None

try:
    a = secrets.randbelow(220) + 1
    b = secrets.randbelow(180) + 20
    base_id = secrets.randbelow(800000) + 100000
    ids = [base_id + i for i in range(6)]

    logs = [
        {"id": ids[0], "request": {"headers": {"Authorization": "Token bad"}}, "response": {"headers": {"Set-Cookie": "sid=a; Secure; HttpOnly"}}},
        {"id": ids[1], "request": {"headers": {"Authorization": "Bearer good"}}, "response": {"headers": {"Set-Cookie": "sid=b; Secure ; HttpOnly"}}},
        {"id": ids[2], "request": {"headers": {}}, "response": {"headers": {"Set-Cookie": "sid=c; Secure"}}},
        {"id": ids[3], "request": {"headers": {"Authorization": ""}}, "response": {"headers": {}}},
        {"id": ids[4], "request": {"headers": {"Authorization": "Bearer fine"}}, "response": {"headers": {"Set-Cookie": "sid=d; NotSecure; HttpOnly"}}},
        {"id": ids[5], "request": {"headers": {"Authorization": "Bearer another"}}, "response": {"headers": {"Content-Type": "application/json"}}},
    ]
    policies = [
        {"src_ip_range": f"10.{a}.{b}.0/24", "dest_port": 8443},
        {"src_ip_range": "172.31.64.0/20", "dest_port": 2222},
    ]
    rows = [
        ["dyn-a", f"10.{a}.{b}.1", "8443"],
        ["dyn-b", f"10.{a}.{b}.254", "8443"],
        ["dyn-c", f"10.{a}.{b}.9", "443"],
        ["dyn-d", f"10.{a}.{b + 1}.9", "8443"],
        ["dyn-e", "172.31.70.8", "2222"],
        ["dyn-f", "172.31.80.8", "2222"],
    ]

    (DATA / "auth_logs.json").write_text(json.dumps(logs, indent=2) + "\n")
    (DATA / "network_policy.json").write_text(json.dumps(policies, indent=2) + "\n")
    with (DATA / "connections.csv").open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["conn_id", "src_ip", "dest_port"])
        writer.writerows(rows)

    protected = ["auth_logs.json", "network_policy.json", "connections.csv"]
    manifest_lines = []
    for name in protected:
        digest = hashlib.sha256((DATA / name).read_bytes()).hexdigest()
        manifest_lines.append(f"{digest}  {name}\n")
    (DATA / "manifest.sha256").write_text("".join(manifest_lines))

    changed = protected[secrets.randbelow(len(protected))]
    with (DATA / changed).open("ab") as f:
        f.write(b"\n")

    manifest_hashes = {}
    for line in (DATA / "manifest.sha256").read_text().splitlines():
        parts = line.split()
        manifest_hashes[parts[1]] = parts[0]
    expected_integrity = {
        name: ("PASS" if hashlib.sha256((DATA / name).read_bytes()).hexdigest() == manifest_hashes[name] else "FAIL")
        for name in protected
    }

    expected_violations = []
    parsed_logs = json.loads((DATA / "auth_logs.json").read_text())
    for entry in parsed_logs:
        req = entry.get("request", {}).get("headers", {})
        res = entry.get("response", {}).get("headers", {})
        violation = "Authorization" in req and not req["Authorization"].startswith("Bearer ")
        if "Set-Cookie" in res:
            directives = [part.strip() for part in res["Set-Cookie"].split(";")]
            violation = violation or "Secure" not in directives or "HttpOnly" not in directives
        if violation:
            expected_violations.append(entry["id"])

    parsed_policies = json.loads((DATA / "network_policy.json").read_text())
    expected_connections = {}
    with (DATA / "connections.csv").open() as f:
        for row in csv.DictReader(f):
            ip = ipaddress.ip_address(row["src_ip"])
            port = int(row["dest_port"])
            allowed = any(
                ip in ipaddress.ip_network(rule["src_ip_range"])
                and port == int(rule["dest_port"])
                for rule in parsed_policies
            )
            expected_connections[row["conn_id"]] = "ALLOWED" if allowed else "DENIED"

    if REPORT.exists():
        REPORT.unlink()
    subprocess.run([sys.executable, str(SCRIPT)], cwd="/home/user", check=True, timeout=20)
    assert REPORT.is_file() and not REPORT.is_symlink(), "audit.py did not create a regular audit_report.json"
    report = json.loads(REPORT.read_text())
    assert report["integrity_checks"] == expected_integrity
    assert sorted(report["auth_violations"]) == sorted(expected_violations)
    assert report["connection_evaluations"] == expected_connections
finally:
    DATA.mkdir(parents=True, exist_ok=True)
    for name, content in original.items():
        (DATA / name).write_bytes(content)
    if original_report is None:
        if REPORT.exists():
            REPORT.unlink()
    else:
        REPORT.write_bytes(original_report)
DYNAMIC_EOF

run_checks() {
    [ -f /home/user/audit.py ] && [ ! -L /home/user/audit.py ] || return 1
    rm -f /home/user/audit_report.json || return 1
    timeout 20s python3 /home/user/audit.py || return 1
    [ -f /home/user/audit_report.json ] && [ ! -L /home/user/audit_report.json ] || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1
    python3 /tmp/test_dynamic_audit.py || return 1
}

if run_checks 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
