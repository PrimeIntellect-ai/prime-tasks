#!/bin/bash
mkdir -p /logs/verifier
status=0

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import stat
import pytest

def test_security_report_json():
    report_path = "/home/user/security_report.json"
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."

    with open(report_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} does not contain valid JSON.")

    assert "suspicious_ips" in data, "JSON report missing 'suspicious_ips' key."
    assert "quarantined_files" in data, "JSON report missing 'quarantined_files' key."

    # Compute expected IPs from log
    log_path = "/home/user/logs/access.log"
    expected_ips = set()
    if os.path.isfile(log_path):
        with open(log_path, 'r') as f:
            for line in f:
                if "GET " in line:
                    parts = line.split()
                    if len(parts) > 6:
                        ip = parts[0]
                        req_path = parts[6]
                        if ".pem" in req_path or ".key" in req_path or "id_rsa" in req_path:
                            expected_ips.add(ip)

    expected_ips_sorted = sorted(list(expected_ips))
    assert data["suspicious_ips"] == expected_ips_sorted, f"Expected suspicious_ips {expected_ips_sorted}, got {data['suspicious_ips']}"

    expected_quarantined = sorted(["backup.txt", "dev_key.pem"])
    assert data["quarantined_files"] == expected_quarantined, f"Expected quarantined_files {expected_quarantined}, got {data['quarantined_files']}"

def test_quarantined_files_and_permissions():
    quarantine_dir = "/home/user/quarantine"
    expected_files = ["backup.txt", "dev_key.pem"]

    for filename in expected_files:
        filepath = os.path.join(quarantine_dir, filename)
        assert os.path.isfile(filepath), f"Expected quarantined file {filepath} is missing."

        # Check permissions (0600)
        st = os.stat(filepath)
        mode = stat.S_IMODE(st.st_mode)
        assert mode == 0o600, f"File {filepath} has incorrect permissions: {oct(mode)}, expected 0o600."

def test_original_files_removed():
    original_paths = [
        "/home/user/web_app/public/docs/backup.txt",
        "/home/user/web_app/public/dev_key.pem"
    ]

    for filepath in original_paths:
        assert not os.path.exists(filepath), f"Vulnerable file {filepath} was not removed from the web root."

def test_sshd_config_snippet():
    snippet_path = "/home/user/sshd_config.snippet"
    assert os.path.isfile(snippet_path), f"SSH config snippet {snippet_path} is missing."

    expected_lines = [
        "PermitRootLogin no",
        "PasswordAuthentication no",
        "X11Forwarding no",
        "MaxAuthTries 3"
    ]

    with open(snippet_path, 'r') as f:
        content = f.read().strip().splitlines()

    # Strip whitespace from each line for robust comparison
    actual_lines = [line.strip() for line in content if line.strip()]

    assert actual_lines == expected_lines, f"SSH config snippet content does not match exactly. Expected {expected_lines}, got {actual_lines}"
TEST_EOF

if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    status=1
fi

if [ ! -f /home/user/policy_enforcer.go ]; then
    echo "Missing /home/user/policy_enforcer.go"
    status=1
fi
if [ ! -f /home/user/policy_enforcer ] || [ ! -x /home/user/policy_enforcer ]; then
    echo "Missing or non-executable /home/user/policy_enforcer"
    status=1
fi

rebuilt=/tmp/policy_enforcer_rebuilt
if [ "$status" -eq 0 ] || [ -f /home/user/policy_enforcer.go ]; then
    if ! go build -o "$rebuilt" /home/user/policy_enforcer.go; then
        echo "The submitted Go source does not compile"
        status=1
    fi
fi

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic.py
import json
import os
import re
import secrets
import stat
import subprocess
import sys

WEB = "/home/user/web_app/public"
LOG = "/home/user/logs/access.log"
QUARANTINE = "/home/user/quarantine"
REPORT = "/home/user/security_report.json"
SNIPPET = "/home/user/sshd_config.snippet"
EXPECTED_SNIPPET = [
    "PermitRootLogin no",
    "PasswordAuthentication no",
    "X11Forwarding no",
    "MaxAuthTries 3",
]

def expected_ips():
    found = set()
    pattern = re.compile(r'^(\S+)\s+.*?"GET\s+(\S+)\s+HTTP/[^\"]+"')
    with open(LOG, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            match = pattern.search(line)
            if match:
                ip, path = match.groups()
                if ".pem" in path or ".key" in path or "id_rsa" in path:
                    found.add(ip)
    return sorted(found)

def private_files():
    found = []
    marker = re.compile(br"-----BEGIN .* PRIVATE KEY-----")
    for root, _, files in os.walk(WEB):
        for name in files:
            path = os.path.join(root, name)
            with open(path, "rb") as f:
                if marker.search(f.read()):
                    found.append((path, name))
    return found

def run_case(executable, sequence):
    token = secrets.token_hex(8)
    nested = os.path.join(WEB, "audit_" + token, "nested")
    os.makedirs(nested, exist_ok=True)
    key_name = f"incident_{sequence}_{token}.data"
    key_path = os.path.join(nested, key_name)
    key_bytes = (b"preamble\n-----BEGIN EC PRIVATE KEY-----\n" + token.encode() +
                 b"\n-----END EC PRIVATE KEY-----\n")
    with open(key_path, "wb") as f:
        f.write(key_bytes)
    os.chmod(key_path, 0o666)

    normal_path = os.path.join(nested, f"normal_{token}.txt")
    with open(normal_path, "w", encoding="utf-8") as f:
        f.write("-----BEGIN PUBLIC KEY-----\nnot private\n")

    octet = 20 + sequence
    ip1 = f"172.29.{octet}.{secrets.randbelow(180) + 20}"
    ip2 = f"172.30.{octet}.{secrets.randbelow(180) + 20}"
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(f'{ip1} - - [11/Sep/2026:12:00:00 +0000] "GET /probe/{token}.pem HTTP/1.1" 404 17\n')
        f.write(f'{ip2} - - [11/Sep/2026:12:00:01 +0000] "GET /keys/{token}.key HTTP/1.1" 403 18\n')
        f.write(f'{ip1} - - [11/Sep/2026:12:00:02 +0000] "GET /again/id_rsa_{token} HTTP/1.1" 404 19\n')
        f.write(f'172.31.{octet}.9 - - [11/Sep/2026:12:00:03 +0000] "POST /ignored/{token}.pem HTTP/1.1" 404 20\n')

    expected_ip_list = expected_ips()
    exposed = private_files()
    expected_names = sorted(name for _, name in exposed)
    original_contents = {path: open(path, "rb").read() for path, _ in exposed}

    for output in (REPORT, SNIPPET):
        try:
            os.remove(output)
        except FileNotFoundError:
            pass

    subprocess.run([executable], check=True, timeout=30)

    assert os.path.isfile(REPORT), "Executable did not create the JSON report"
    with open(REPORT, "r", encoding="utf-8") as f:
        data = json.load(f)
    assert set(data.keys()) == {"suspicious_ips", "quarantined_files"}
    assert data["suspicious_ips"] == expected_ip_list
    assert data["quarantined_files"] == expected_names

    for old_path, name in exposed:
        assert not os.path.exists(old_path), f"Private key remained in web root: {old_path}"
        destination = os.path.join(QUARANTINE, name)
        assert os.path.isfile(destination), f"Missing quarantined file: {destination}"
        assert stat.S_IMODE(os.stat(destination).st_mode) == 0o600
        with open(destination, "rb") as f:
            assert f.read() == original_contents[old_path]

    assert os.path.isfile(normal_path), "A non-private-key file was incorrectly moved"
    assert os.path.isfile(SNIPPET), "Executable did not create the SSH snippet"
    with open(SNIPPET, "r", encoding="utf-8") as f:
        actual = [line.strip() for line in f.read().strip().splitlines() if line.strip()]
    assert actual == EXPECTED_SNIPPET

if __name__ == "__main__":
    run_case(sys.argv[1], int(sys.argv[2]))
DYNAMIC_EOF

if [ -f /home/user/policy_enforcer ] && [ -x /home/user/policy_enforcer ]; then
    if ! python3 /tmp/test_dynamic.py /home/user/policy_enforcer 1; then
        echo "Submitted compiled executable failed dynamic behavioral testing"
        status=1
    fi
fi

if [ -f "$rebuilt" ] && [ -x "$rebuilt" ]; then
    if ! python3 /tmp/test_dynamic.py "$rebuilt" 2; then
        echo "Executable rebuilt from submitted Go source failed dynamic behavioral testing"
        status=1
    fi
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
