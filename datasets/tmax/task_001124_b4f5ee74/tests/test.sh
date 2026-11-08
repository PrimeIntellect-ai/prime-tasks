#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
from collections import Counter
import json
import re
from pathlib import Path
from urllib.parse import parse_qsl, unquote, urlsplit

import pytest

AUDIT_REPORT_PATH = "/home/user/compliance_audit.json"
REDACTED_LOGS_PATH = "/home/user/redacted_logs.log"
SOURCE_LOGS_PATH = "/home/user/server_logs.log"
CONFIG_ROOT = Path("/home/user/system_configs")

EXPECTED_SOURCE_LOG = """2023-10-01T12:00:01 192.168.1.10 GET /login?redirect=L2Rhc2hib2FyZA%3D%3D 200 - User-Agent: Mozilla/5.0
2023-10-01T12:05:22 10.0.0.5 GET /api/data?ssn=123-45-6789 200 - User-Agent: curl/7.68.0
2023-10-01T12:10:05 172.16.0.4 GET /login?redirect=amF2YXNjcmlwdDphbGVydCgxKQ%3D%3D 200 - User-Agent: EvilCorp
2023-10-01T12:15:00 192.168.1.11 GET /profile Header: Bearer abcdef1234567890ABCD== 200
2023-10-01T12:20:10 10.10.10.10 GET /login?redirect=PHNjcmlwdD5zdGVhbCgpPC9zY3JpcHQ%2B 200 - User-Agent: HackerTracker
2023-10-01T12:25:00 192.168.1.12 GET /settings?ssn=987-65-4321 Header: Bearer XYZxyz9876543210abcd== 200
"""

SSN_RE = re.compile(r"\b\d{3}-\d{2}-\d{4}\b")
TOKEN_RE = re.compile(r"Bearer [A-Za-z0-9+/=]{16,}")


def get_audit_report():
    path = Path(AUDIT_REPORT_PATH)
    assert path.exists(), f"Audit report is missing at {AUDIT_REPORT_PATH}"
    assert path.is_file(), f"Path {AUDIT_REPORT_PATH} exists but is not a file"

    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Audit report at {AUDIT_REPORT_PATH} is not valid JSON: {e}")


def test_audit_report_malicious_ips():
    """Verify the malicious IPs are correctly identified."""
    report = get_audit_report()
    assert "malicious_ips" in report, "Key 'malicious_ips' is missing from the audit report."

    expected_ips = {"172.16.0.4", "10.10.10.10"}
    actual_ips = set(report["malicious_ips"])

    assert actual_ips == expected_ips, (
        f"Malicious IPs do not match expected values.\n"
        f"Expected: {expected_ips}\n"
        f"Found: {actual_ips}"
    )


def test_audit_report_decoded_payloads():
    """Verify the decoded XSS payloads are correctly identified."""
    report = get_audit_report()
    assert "decoded_xss_payloads" in report, "Key 'decoded_xss_payloads' is missing from the audit report."

    expected_payloads = {"javascript:alert(1)", "<script>steal()</script>"}
    actual_payloads = set(report["decoded_xss_payloads"])

    assert actual_payloads == expected_payloads, (
        f"Decoded XSS payloads do not match expected values.\n"
        f"Expected: {expected_payloads}\n"
        f"Found: {actual_payloads}"
    )


def test_audit_report_privesc_vuln():
    """Verify the privilege escalation vulnerability file is correctly identified."""
    report = get_audit_report()
    assert "privesc_vuln_file" in report, "Key 'privesc_vuln_file' is missing from the audit report."

    expected_file = "/home/user/system_configs/sudoers.d/02-backup-vuln"
    actual_file = report["privesc_vuln_file"]

    assert actual_file == expected_file, (
        f"Privilege escalation vulnerability file is incorrect.\n"
        f"Expected: '{expected_file}'\n"
        f"Found: '{actual_file}'"
    )


def test_audit_report_redacted_count():
    """Verify the redacted log lines count is correct."""
    report = get_audit_report()
    assert "redacted_log_lines_count" in report, "Key 'redacted_log_lines_count' is missing from the audit report."

    expected_count = 3
    actual_count = report["redacted_log_lines_count"]

    assert actual_count == expected_count, (
        f"Redacted log lines count is incorrect.\n"
        f"Expected: {expected_count}\n"
        f"Found: {actual_count}"
    )


def test_redacted_logs_exist_and_correctly_redacted():
    """Verify the redacted logs file exists and sensitive data is properly masked."""
    path = Path(REDACTED_LOGS_PATH)
    assert path.exists(), f"Redacted logs file is missing at {REDACTED_LOGS_PATH}"
    assert path.is_file(), f"Path {REDACTED_LOGS_PATH} exists but is not a file"

    content = path.read_text(encoding="utf-8")

    assert "123-45-6789" not in content, "Found unredacted SSN (123-45-6789) in the redacted logs."
    assert "987-65-4321" not in content, "Found unredacted SSN (987-65-4321) in the redacted logs."
    assert "abcdef1234567890ABCD==" not in content, "Found unredacted Bearer token in the redacted logs."
    assert "XYZxyz9876543210abcd==" not in content, "Found unredacted Bearer token in the redacted logs."

    ssn_redaction_count = content.count("[REDACTED_SSN]")
    assert ssn_redaction_count == 2, (
        f"Expected exactly 2 occurrences of '[REDACTED_SSN]', found {ssn_redaction_count}."
    )

    token_redaction_count = content.count("Bearer [REDACTED_TOKEN]")
    assert token_redaction_count == 2, (
        f"Expected exactly 2 occurrences of 'Bearer [REDACTED_TOKEN]', found {token_redaction_count}."
    )


def derive_malicious_requests(source):
    ips = []
    payloads = []
    for line in source.splitlines():
        match = re.match(r"^\S+\s+(\S+)\s+GET\s+(\S+)", line)
        if not match:
            continue
        ip, target = match.groups()
        for key, encoded in parse_qsl(urlsplit(target).query, keep_blank_values=True):
            if key != "redirect":
                continue
            try:
                raw = encoded.encode("ascii")
                raw += b"=" * ((-len(raw)) % 4)
                decoded = base64.b64decode(raw, validate=True).decode("utf-8")
                decoded = unquote(decoded)
            except (ValueError, UnicodeError):
                continue
            if "<script>" in decoded or "javascript:" in decoded:
                ips.append(ip)
                payloads.append(decoded)
    return ips, payloads


def derive_nopasswd_root_files():
    vulnerable = []
    for path in CONFIG_ROOT.rglob("*"):
        if not path.is_file():
            continue
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError:
            continue
        for line in lines:
            rule = line.split("#", 1)[0].strip()
            if not rule or "NOPASSWD:" not in rule:
                continue
            runas = re.search(r"=\s*\(([^)]*)\)", rule)
            if runas and ({p.strip() for p in runas.group(1).split(",")} & {"root", "ALL"}):
                vulnerable.append(str(path))
                break
    return vulnerable


def test_outputs_are_derived_from_and_preserve_the_supplied_inputs():
    source_path = Path(SOURCE_LOGS_PATH)
    assert source_path.is_file(), f"Source log is missing at {SOURCE_LOGS_PATH}"
    source = source_path.read_text(encoding="utf-8")
    assert source == EXPECTED_SOURCE_LOG, "The supplied source log was modified."

    redacted = Path(REDACTED_LOGS_PATH).read_text(encoding="utf-8")
    expected_redacted = SSN_RE.sub("[REDACTED_SSN]", source)
    expected_redacted = TOKEN_RE.sub("Bearer [REDACTED_TOKEN]", expected_redacted)
    assert redacted == expected_redacted, (
        "redacted_logs.log must preserve the complete source log exactly except for the required redactions."
    )

    source_lines = source.splitlines(keepends=True)
    redacted_lines = redacted.splitlines(keepends=True)
    assert len(source_lines) == 6
    assert len(redacted_lines) == len(source_lines), "The redacted log must preserve all six source lines."
    changed_count = sum(a != b for a, b in zip(source_lines, redacted_lines))

    report = get_audit_report()
    expected_ips, expected_payloads = derive_malicious_requests(source)
    assert Counter(report["malicious_ips"]) == Counter(expected_ips), (
        "malicious_ips does not match the malicious redirect requests derived from the source log."
    )
    assert Counter(report["decoded_xss_payloads"]) == Counter(expected_payloads), (
        "decoded_xss_payloads does not match the decoded redirect parameters in the source log."
    )
    assert report["redacted_log_lines_count"] == changed_count, (
        "redacted_log_lines_count does not equal the number of source lines changed by redaction."
    )

    vulnerable_files = derive_nopasswd_root_files()
    assert vulnerable_files == ["/home/user/system_configs/sudoers.d/02-backup-vuln"], (
        f"Expected exactly the supplied passwordless-root sudoers vulnerability, found: {vulnerable_files}"
    )
    assert report["privesc_vuln_file"] == vulnerable_files[0], (
        "privesc_vuln_file does not identify the configuration file containing the derived vulnerability."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
