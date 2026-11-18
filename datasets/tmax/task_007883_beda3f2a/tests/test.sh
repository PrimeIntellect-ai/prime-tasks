#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import stat
import string
import subprocess
import urllib.parse

EVIDENCE_DIR = "/home/user/incident/evidence"
REQUESTS_LOG = os.path.join(EVIDENCE_DIR, "requests.log")
SCANNER_SOURCE = "/home/user/incident/scanner.c"
CSP_FILE = "/home/user/incident/csp_policy.txt"
REPORT_FILE = "/home/user/incident/report.txt"
EXPECTED_CSP = "default-src 'self'; script-src 'self' 'nonce-r4nd0m123';"


def decoded_findings(path):
    findings = []
    with open(path, "r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.rstrip("\r\n")
            if not line:
                continue
            ip, encoded = line.split("|", 1)
            url_encoded = base64.b64decode(encoded, validate=True).decode("utf-8")
            decoded = urllib.parse.unquote_plus(url_encoded)
            if "<svg onload=" in decoded or "SELECT * FROM" in decoded:
                findings.append((ip, decoded))
    return findings


def test_evidence_directory_permissions():
    assert os.path.isdir(EVIDENCE_DIR), f"Directory {EVIDENCE_DIR} does not exist."
    perms = stat.S_IMODE(os.stat(EVIDENCE_DIR).st_mode)
    assert perms == 0o700, (
        f"Permissions on {EVIDENCE_DIR} are {oct(perms)}, expected exactly 0o700."
    )


def test_csp_policy_content():
    assert os.path.isfile(CSP_FILE), f"File {CSP_FILE} does not exist."
    with open(CSP_FILE, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert content == EXPECTED_CSP, (
        f"CSP policy content is incorrect. Expected: '{EXPECTED_CSP}', got: '{content}'"
    )


def test_report_content_matches_supplied_log_exactly():
    assert os.path.isfile(REPORT_FILE), f"Report file {REPORT_FILE} does not exist."
    findings = decoded_findings(REQUESTS_LOG)
    expected_lines = [
        "Evidence Secured: Yes",
        "Malicious Payloads:",
        *[f"{ip} - {payload}" for ip, payload in findings],
        f"Fixed CSP: {EXPECTED_CSP}",
    ]

    with open(REPORT_FILE, "r", encoding="utf-8") as f:
        actual_lines = f.read().strip().splitlines()

    assert actual_lines == expected_lines, (
        "Report does not exactly match the malicious payloads derived by Base64- and "
        f"URL-decoding requests.log. Expected {expected_lines!r}, got {actual_lines!r}"
    )
    assert "192.168.1.10" not in "\n".join(actual_lines)
    assert "192.168.1.11" not in "\n".join(actual_lines)


def encode_payload(payload):
    url_encoded = urllib.parse.quote(payload, safe="")
    return base64.b64encode(url_encoded.encode("utf-8")).decode("ascii")


def test_scanner_exists_compiles_and_scans_dynamic_inputs():
    assert os.path.isfile(SCANNER_SOURCE), f"C source file {SCANNER_SOURCE} does not exist."

    executable = "/tmp/incident_scanner_test"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", SCANNER_SOURCE, "-o", executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, f"scanner.c failed to compile:\n{compile_result.stderr}"

    alphabet = string.ascii_lowercase + string.digits
    marker = "".join(secrets.choice(alphabet) for _ in range(12))
    malicious = [
        ("198.51.100.21", f"prefix <svg onload=alert('{marker}')> suffix"),
        ("198.51.100.22", f"SELECT * FROM table_{marker}"),
    ]
    non_malicious = [
        ("203.0.113.31", f"SELECT $ FROM table_{marker}"),
        ("203.0.113.32", f"<svg onload =alert('{marker}')>"),
        ("203.0.113.33", f"ordinary request {marker}"),
    ]
    cases = malicious + non_malicious
    replacement_log = "".join(
        f"{ip}|{encode_payload(payload)}\n" for ip, payload in cases
    ).encode("utf-8")

    with open(REQUESTS_LOG, "rb") as f:
        original_log = f.read()
    original_report = None
    if os.path.exists(REPORT_FILE):
        with open(REPORT_FILE, "rb") as f:
            original_report = f.read()

    try:
        with open(REQUESTS_LOG, "wb") as f:
            f.write(replacement_log)

        run_result = subprocess.run(
            [executable],
            cwd="/home/user/incident",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            timeout=20,
        )
        assert run_result.returncode == 0, (
            f"Compiled scanner exited with {run_result.returncode}. Output:\n{run_result.stdout}"
        )

        output_lines = run_result.stdout.splitlines()
        for ip, payload in malicious:
            matching = [line for line in output_lines if ip in line and payload in line]
            assert matching, (
                f"Scanner output did not identify and fully decode malicious input "
                f"{ip}|{payload!r}. Output was:\n{run_result.stdout}"
            )

        for ip, _ in non_malicious:
            matching = [line for line in output_lines if ip in line]
            for line in matching:
                label = line.lower()
                assert any(word in label for word in ("benign", "safe", "not malicious")), (
                    f"Scanner appears to classify near-miss or benign input {ip} as malicious: {line!r}"
                )
    finally:
        with open(REQUESTS_LOG, "wb") as f:
            f.write(original_log)
        if original_report is not None:
            with open(REPORT_FILE, "wb") as f:
                f.write(original_report)
        elif os.path.exists(REPORT_FILE):
            os.remove(REPORT_FILE)
        if os.path.exists(executable):
            os.remove(executable)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
