#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
from collections import Counter

import pytest

RESULTS_DIR = "/home/user/audit_task/results"
RAW_DATA_DIR = "/home/user/audit_task/raw_data"

ORIGINAL_LOGS = '''{"timestamp": "2023-10-01T10:00:00Z", "ip": "192.168.1.50", "event_type": "failed_login", "password": "password123"}
{"timestamp": "2023-10-01T10:01:00Z", "ip": "192.168.1.50", "event_type": "failed_login", "password": "admin"}
{"timestamp": "2023-10-01T10:02:00Z", "ip": "192.168.1.50", "event_type": "failed_login", "password": "root"}
{"timestamp": "2023-10-01T10:03:00Z", "ip": "192.168.1.50", "event_type": "failed_login", "password": "123"}
{"timestamp": "2023-10-01T10:04:00Z", "ip": "10.0.0.5", "event_type": "success", "secret_token": "abc123xyz"}
{"timestamp": "2023-10-01T10:05:00Z", "ip": "172.16.0.2", "event_type": "failed_login", "password": "qwerty"}
{"timestamp": "2023-10-01T10:06:00Z", "ip": "172.16.0.2", "event_type": "failed_login", "password": "password"}
{"timestamp": "2023-10-01T10:07:00Z", "ip": "172.16.0.2", "event_type": "failed_login", "password": "letmein"}
{"timestamp": "2023-10-01T10:08:00Z", "ip": "172.16.0.2", "event_type": "failed_login", "password": "admin"}
{"timestamp": "2023-10-01T10:09:00Z", "ip": "172.16.0.2", "event_type": "failed_login", "password": "root"}
{"timestamp": "2023-10-01T10:10:00Z", "ip": "10.0.0.8", "event_type": "failed_login", "password": "foo"}
'''

ORIGINAL_SSHD = '''# Default sshd_config
Port 22
#PermitRootLogin yes
MaxAuthTries 6
#PasswordAuthentication yes
PubkeyAuthentication yes
'''

ORIGINAL_BINARIES = {
    "ls": b"echo 'ls'\n",
    "cat": b"echo 'cat'\n",
    "ps": b"echo 'malicious rootkit'\n",
    "grep": b"echo 'grep'\n",
}


def read_raw_entries():
    path = os.path.join(RAW_DATA_DIR, "auth_logs.jsonl")
    with open(path, "r", encoding="utf-8") as f:
        return [json.loads(line) for line in f]


def redact(value):
    if isinstance(value, dict):
        return {
            key: "[REDACTED]" if key in ("password", "secret_token") else redact(item)
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [redact(item) for item in value]
    return value


def expected_malicious_ips():
    counts = Counter(
        entry["ip"]
        for entry in read_raw_entries()
        if entry.get("event_type") == "failed_login" and "ip" in entry
    )
    return sorted(ip for ip, count in counts.items() if count > 3)


def parse_checksum_file():
    records = []
    path = os.path.join(RAW_DATA_DIR, "checksums.sha256")
    with open(path, "r", encoding="utf-8") as f:
        for number, line in enumerate(f, 1):
            match = re.fullmatch(r"([0-9a-fA-F]{64}) [ *](\S+)\n?", line)
            assert match, f"Malformed checksum record on line {number}."
            records.append((match.group(1).lower(), match.group(2)))
    return records


def compromised_files():
    mismatches = []
    for expected_hash, relative_path in parse_checksum_file():
        full_path = os.path.join(RAW_DATA_DIR, relative_path)
        assert os.path.isfile(full_path), f"Checksummed file is missing: {relative_path}"
        with open(full_path, "rb") as f:
            actual_hash = hashlib.sha256(f.read()).hexdigest()
        if actual_hash != expected_hash:
            mismatches.append(relative_path)
    return mismatches


def expected_secure_sshd():
    output = []
    found = set()
    directive = re.compile(
        r"^(?P<indent>\s*)#?\s*(?P<name>PermitRootLogin|PasswordAuthentication)\s+\S+.*?(?P<newline>\r?\n)?$"
    )
    for line in ORIGINAL_SSHD.splitlines(keepends=True):
        match = directive.match(line)
        if match:
            name = match.group("name")
            found.add(name)
            output.append(f'{match.group("indent")}{name} no{match.group("newline") or ""}')
        else:
            output.append(line)
    assert found == {"PermitRootLogin", "PasswordAuthentication"}
    return "".join(output)


def test_raw_inputs_unchanged():
    with open(os.path.join(RAW_DATA_DIR, "auth_logs.jsonl"), "r", encoding="utf-8") as f:
        assert f.read() == ORIGINAL_LOGS, "The supplied authentication log was modified."
    with open(os.path.join(RAW_DATA_DIR, "sshd_config.insecure"), "r", encoding="utf-8") as f:
        assert f.read() == ORIGINAL_SSHD, "The supplied SSH configuration was modified."

    bin_dir = os.path.join(RAW_DATA_DIR, "bin")
    assert sorted(os.listdir(bin_dir)) == sorted(ORIGINAL_BINARIES)
    for name, expected_content in ORIGINAL_BINARIES.items():
        with open(os.path.join(bin_dir, name), "rb") as f:
            assert f.read() == expected_content, f"The supplied bin/{name} file was modified."

    records = parse_checksum_file()
    assert [path for _, path in records] == ["bin/ls", "bin/cat", "bin/ps", "bin/grep"]
    for digest, path in records:
        if path == "bin/ps":
            assert digest == hashlib.sha256(b"").hexdigest()
        else:
            assert digest == hashlib.sha256(ORIGINAL_BINARIES[os.path.basename(path)]).hexdigest()


def test_results_directory_exists():
    assert os.path.isdir(RESULTS_DIR), f"Results directory missing: {RESULTS_DIR}"


def test_audit_summary():
    summary_file = os.path.join(RESULTS_DIR, "audit_summary.json")
    assert os.path.isfile(summary_file), f"Audit summary file missing: {summary_file}"

    with open(summary_file, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {summary_file} is not valid JSON.")

    assert "compromised_file" in data, "Missing 'compromised_file' key in audit summary."
    assert data["compromised_file"] in ["ps", "bin/ps"], f"Incorrect compromised file identified: {data['compromised_file']}"
    assert "malicious_ips_count" in data, "Missing 'malicious_ips_count' key in audit summary."

    mismatches = compromised_files()
    assert len(mismatches) == 1, f"Expected exactly one checksum mismatch, found: {mismatches}"
    expected = {
        "compromised_file": os.path.basename(mismatches[0]),
        "malicious_ips_count": len(expected_malicious_ips()),
    }
    assert data == expected, f"Audit summary does not match the supplied data. Got: {data}"


def test_firewall_rules():
    rules_file = os.path.join(RESULTS_DIR, "firewall_rules.txt")
    assert os.path.isfile(rules_file), f"Firewall rules file missing: {rules_file}"

    with open(rules_file, "r", encoding="utf-8") as f:
        content = f.read()
    lines = [line.strip() for line in content.splitlines() if line.strip()]
    expected_lines = [
        f"iptables -A INPUT -s {ip} -j DROP" for ip in expected_malicious_ips()
    ]

    assert lines == expected_lines, f"Firewall rules do not match expected sorted output. Got: {lines}"
    assert content.splitlines() == expected_lines, "Firewall rules contain blank, extra, or malformed lines."


def test_sshd_hardening():
    secure_sshd = os.path.join(RESULTS_DIR, "sshd_config.secure")
    assert os.path.isfile(secure_sshd), f"Secure SSH config missing: {secure_sshd}"

    with open(secure_sshd, "r", encoding="utf-8") as f:
        content = f.read()
    lines = [line.strip() for line in content.splitlines()]

    assert "PermitRootLogin no" in lines, "Missing or incorrect 'PermitRootLogin no' directive."
    assert "PasswordAuthentication no" in lines, "Missing or incorrect 'PasswordAuthentication no' directive."
    assert not any(re.match(r"^\s*#\s*PermitRootLogin\s+yes", line) for line in lines), "Original commented '#PermitRootLogin yes' is still present."
    assert not any(re.match(r"^\s*#\s*PasswordAuthentication\s+yes", line) for line in lines), "Original commented '#PasswordAuthentication yes' is still present."
    assert content == expected_secure_sshd(), "Secure SSH config differs from the input beyond the required modifications."


def test_redacted_logs():
    redacted_file = os.path.join(RESULTS_DIR, "redacted_logs.jsonl")
    assert os.path.isfile(redacted_file), f"Redacted logs file missing: {redacted_file}"

    with open(redacted_file, "r", encoding="utf-8") as f:
        lines = f.readlines()

    originals = read_raw_entries()
    assert len(lines) == len(originals), f"Expected exactly {len(originals)} log entries in redacted logs, but found {len(lines)}."

    for i, (line, original) in enumerate(zip(lines, originals)):
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} in {redacted_file} is not valid JSON.")

        if "password" in entry:
            assert entry["password"] == "[REDACTED]", f"Password not correctly redacted on line {i+1}."
        if "secret_token" in entry:
            assert entry["secret_token"] == "[REDACTED]", f"Secret token not correctly redacted on line {i+1}."
        assert entry == redact(original), f"Log entry {i+1} was changed beyond the required redaction."
        assert "password123" not in line, f"Plaintext 'password123' leaked on line {i+1}."
        assert "abc123xyz" not in line, f"Plaintext 'abc123xyz' leaked on line {i+1}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
