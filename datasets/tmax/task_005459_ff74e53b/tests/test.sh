#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import stat
import pytest

def test_mitigation_directory_exists():
    """Test that the mitigation directory was created."""
    assert os.path.isdir("/home/user/mitigation"), "/home/user/mitigation directory is missing"

def test_payloads_file_content_and_permissions():
    """Test payloads.txt content and permissions."""
    payloads_file = "/home/user/mitigation/payloads.txt"
    assert os.path.isfile(payloads_file), f"{payloads_file} is missing"

    # Check permissions
    st = os.stat(payloads_file)
    permissions = stat.S_IMODE(st.st_mode)
    assert permissions == 0o400, f"Permissions for {payloads_file} are {oct(permissions)}, expected 0o400"

    # Check content
    with open(payloads_file, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_payloads = {
        "<script>fetch('http://evil-corp.com')</script>",
        "ls; cat /etc/passwd",
        "<script>alert(1)</script>"
    }

    assert set(lines) == expected_payloads, f"Content of {payloads_file} does not match expected unique malicious payloads"

def test_block_ips_script_content():
    """Test block_ips.sh content."""
    script_file = "/home/user/mitigation/block_ips.sh"
    assert os.path.isfile(script_file), f"{script_file} is missing"

    with open(script_file, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_rules = {
        "ufw deny from 192.168.1.105",
        "ufw deny from 10.0.0.55"
    }

    assert set(lines) == expected_rules, f"Content of {script_file} does not match expected firewall rules"

def test_csp_txt_content():
    """Test csp.txt content."""
    csp_file = "/home/user/mitigation/csp.txt"
    assert os.path.isfile(csp_file), f"{csp_file} is missing"

    with open(csp_file, "r") as f:
        content = f.read().strip()

    expected_csp = "default-src 'self'; script-src 'self';"
    assert content == expected_csp, f"Content of {csp_file} is incorrect"

def test_analyze_go_exists():
    """Test that the analyze.go program exists."""
    assert os.path.isfile("/home/user/analyze.go"), "/home/user/analyze.go is missing"
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_analyze_program.py
import base64
import os
import secrets
import shutil
import stat
import subprocess

source = "/home/user/analyze.go"
binary = "/tmp/analyze_submission"
access_log = "/home/user/evidence/access.log"
mitigation = "/home/user/mitigation"
backup_mitigation = f"/home/user/.mitigation.verifier-{secrets.token_hex(12)}"

assert os.path.isfile(source), f"{source} is missing or is not a regular file"
subprocess.run(
    ["go", "build", "-o", binary, source],
    check=True,
    timeout=30,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)

nonce = secrets.token_hex(12)
records = [
    ("198.51.100.41", "GET", f"ordinary request {nonce}"),
    ("198.51.100.42", "GET", f"<script>probe-{nonce}</script>"),
    ("198.51.100.43", "POST", f"run-{nonce}; cat /etc/shadow"),
    ("198.51.100.44", "GET", f"prefix <script>second-{nonce}</script> suffix"),
    ("198.51.100.45", "POST", f"run-{nonce}; cat /etc/shadow"),
    ("198.51.100.42", "GET", f"harmless followup {nonce}"),
]

expected_payloads = set()
expected_ips = set()
log_lines = []
for index, (ip, method, payload) in enumerate(records):
    encoded = base64.b64encode(payload.encode("utf-8")).decode("ascii")
    log_lines.append(
        f"[2026-01-01T00:00:{index:02d}Z] {ip} {method} /dynamic?payload={encoded}"
    )
    if "<script>" in payload or "cat /etc" in payload:
        expected_payloads.add(payload)
        expected_ips.add(ip)

original_log = open(access_log, "rb").read()
original_log_mode = stat.S_IMODE(os.stat(access_log).st_mode)
mitigation_was_present = os.path.lexists(mitigation)


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)

try:
    if mitigation_was_present:
        os.rename(mitigation, backup_mitigation)

    with open(access_log, "w", encoding="utf-8") as f:
        f.write("\n".join(log_lines) + "\n")

    subprocess.run(
        [binary],
        check=True,
        timeout=20,
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    assert os.path.isdir(mitigation), "Program did not create /home/user/mitigation"
    payloads_path = os.path.join(mitigation, "payloads.txt")
    rules_path = os.path.join(mitigation, "block_ips.sh")
    csp_path = os.path.join(mitigation, "csp.txt")
    assert os.path.isfile(payloads_path), "Program did not create payloads.txt"
    assert os.path.isfile(rules_path), "Program did not create block_ips.sh"
    assert os.path.isfile(csp_path), "Program did not create csp.txt"

    with open(payloads_path, "r", encoding="utf-8") as f:
        payload_lines = [line for line in f.read().splitlines() if line]
    assert set(payload_lines) == expected_payloads, "Program produced incorrect payloads for dynamic input"
    assert len(payload_lines) == len(expected_payloads), "Program did not emit unique malicious payloads"

    with open(rules_path, "r", encoding="utf-8") as f:
        rule_lines = [line.strip() for line in f.readlines() if line.strip()]
    expected_rules = {f"ufw deny from {ip}" for ip in expected_ips}
    assert set(rule_lines) == expected_rules, "Program produced incorrect firewall rules for dynamic input"
    assert len(rule_lines) == len(expected_rules), "Program did not emit unique attacker-IP rules"

    with open(csp_path, "r", encoding="utf-8") as f:
        assert f.read().strip() == "default-src 'self'; script-src 'self';", "Program produced an incorrect CSP"
finally:
    with open(access_log, "wb") as f:
        f.write(original_log)
    os.chmod(access_log, original_log_mode)
    if os.path.lexists(mitigation):
        remove_path(mitigation)
    if mitigation_was_present and os.path.lexists(backup_mitigation):
        os.rename(backup_mitigation, mitigation)
DYNAMIC_EOF

passed=1
if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    passed=0
fi
if [ "$passed" -eq 1 ]; then
    if ! python3 /tmp/test_analyze_program.py 2>&1; then
        passed=0
    fi
fi

echo "$passed" > /logs/verifier/reward.txt
