#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import re
import glob
import hashlib
import secrets
import subprocess
from datetime import datetime
import pytest


def test_decrypted_key_validity():
    """Verify the decrypted private key exists, is unencrypted, and is valid."""
    key_path = "/home/user/certs/decrypted_app.key"
    assert os.path.isfile(key_path), f"Decrypted key file is missing at {key_path}."

    with open(key_path, "r") as f:
        content = f.read()

    assert "ENCRYPTED" not in content, f"The key at {key_path} still appears to be encrypted."
    assert "PRIVATE KEY" in content, f"The file at {key_path} does not appear to be a PEM-encoded private key."

    result = subprocess.run(
        ["openssl", "rsa", "-in", key_path, "-check", "-noout"],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"OpenSSL failed to validate the decrypted key: {result.stderr}"


def test_decrypted_key_is_from_encrypted_source():
    """Derive the PIN from the log and verify both key files contain the same RSA key."""
    log_path = "/home/user/logs/process_exec.log"
    encrypted_path = "/home/user/certs/encrypted_app.key"
    decrypted_path = "/home/user/certs/decrypted_app.key"

    assert os.path.isfile(log_path), f"Process execution log is missing at {log_path}."
    assert os.path.isfile(encrypted_path), f"Encrypted key is missing at {encrypted_path}."

    with open(log_path, "r") as f:
        log_content = f.read()
    hashes = re.findall(r'--pin-hash\s+([0-9a-fA-F]{32})(?:\s|$)', log_content)
    assert hashes, "No MD5 deployment PIN hash was found in the process execution log."
    target_hash = hashes[0].lower()

    pin = None
    for value in range(10000):
        candidate = f"{value:04d}"
        if hashlib.md5(candidate.encode()).hexdigest() == target_hash:
            pin = candidate
            break
    assert pin is not None, "The logged hash does not correspond to a 4-digit numeric PIN."

    encrypted_pub = subprocess.run(
        ["openssl", "pkey", "-in", encrypted_path, "-passin", f"pass:{pin}",
         "-pubout", "-outform", "DER"],
        capture_output=True
    )
    assert encrypted_pub.returncode == 0, (
        "The PIN derived from the process log could not decrypt encrypted_app.key: "
        + encrypted_pub.stderr.decode(errors="replace")
    )

    decrypted_pub = subprocess.run(
        ["openssl", "pkey", "-in", decrypted_path, "-pubout", "-outform", "DER"],
        capture_output=True
    )
    assert decrypted_pub.returncode == 0, "Could not extract the public key from decrypted_app.key."
    assert decrypted_pub.stdout == encrypted_pub.stdout, (
        "decrypted_app.key was not derived from encrypted_app.key."
    )


def test_certificate_validity_and_match():
    """Verify the certificate exists, matches the private key, and has the correct CN."""
    cert_path = "/home/user/certs/app.crt"
    key_path = "/home/user/certs/decrypted_app.key"

    assert os.path.isfile(cert_path), f"Certificate file is missing at {cert_path}."

    subj_result = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-subject", "-noout"],
        capture_output=True,
        text=True
    )
    assert subj_result.returncode == 0, f"Failed to read certificate subject: {subj_result.stderr}"

    normalized_subj = subj_result.stdout.replace(" ", "")
    assert "CN=secure.local" in normalized_subj, f"Certificate Subject does not contain CN=secure.local. Actual output: {subj_result.stdout.strip()}"

    cert_mod_result = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-modulus", "-noout"],
        capture_output=True,
        text=True
    )
    key_mod_result = subprocess.run(
        ["openssl", "rsa", "-in", key_path, "-modulus", "-noout"],
        capture_output=True,
        text=True
    )

    assert cert_mod_result.returncode == 0, "Failed to extract certificate modulus."
    assert key_mod_result.returncode == 0, "Failed to extract private key modulus."

    cert_modulus = cert_mod_result.stdout.strip()
    key_modulus = key_mod_result.stdout.strip()
    assert cert_modulus == key_modulus, "The generated certificate does not match the decrypted private key."


def test_certificate_exact_cn_and_365_day_validity():
    cert_path = "/home/user/certs/app.crt"

    subject = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-noout", "-subject", "-nameopt", "RFC2253"],
        capture_output=True,
        text=True
    )
    assert subject.returncode == 0, f"Failed to inspect certificate subject: {subject.stderr}"
    subject_text = subject.stdout.strip()
    if subject_text.startswith("subject="):
        subject_text = subject_text[len("subject="):]
    common_names = re.findall(r'(?:^|,)CN=([^,]*)', subject_text)
    assert common_names == ["secure.local"], f"Certificate CN must be exactly secure.local; subject was {subject.stdout.strip()}"

    dates = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-noout", "-dates"],
        capture_output=True,
        text=True
    )
    assert dates.returncode == 0, f"Failed to inspect certificate validity: {dates.stderr}"
    parsed = {}
    for line in dates.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            parsed[key] = value
    assert "notBefore" in parsed and "notAfter" in parsed, "Certificate validity dates are missing."
    not_before = datetime.strptime(parsed["notBefore"], "%b %d %H:%M:%S %Y %Z")
    not_after = datetime.strptime(parsed["notAfter"], "%b %d %H:%M:%S %Y %Z")
    assert (not_after - not_before).total_seconds() == 365 * 24 * 60 * 60, (
        "Certificate validity must be exactly 365 days."
    )


def derive_expected_leaks(scripts_dir):
    expected_leaks = []
    script_files = glob.glob(os.path.join(scripts_dir, "*.sh"))
    for filepath in script_files:
        with open(filepath, "r") as f:
            lines = f.readlines()
        for i, line in enumerate(lines):
            match_long = re.search(r'--password=(\S+)', line)
            match_short = re.search(r'-p (\S+)', line)
            if match_long:
                expected_leaks.append({
                    "file": filepath,
                    "line_number": i + 1,
                    "leaked_password": match_long.group(1)
                })
            elif match_short:
                expected_leaks.append({
                    "file": filepath,
                    "line_number": i + 1,
                    "leaked_password": match_short.group(1)
                })
    expected_leaks.sort(key=lambda x: (x["file"], x["line_number"]))
    return expected_leaks


def test_leak_report_json():
    """Verify the leak report exists and matches the expected derived JSON output."""
    report_path = "/home/user/leak_report.json"
    scripts_dir = "/home/user/scripts"

    assert os.path.isfile(report_path), f"Leak report is missing at {report_path}."
    expected_leaks = derive_expected_leaks(scripts_dir)

    with open(report_path, "r") as f:
        try:
            actual_json = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {report_path} does not contain valid JSON.")

    assert "leaks" in actual_json, "The JSON report is missing the top-level 'leaks' key."
    assert isinstance(actual_json["leaks"], list), "The 'leaks' key must contain a list."

    actual_leaks_sorted = sorted(actual_json["leaks"], key=lambda x: (x.get("file", ""), x.get("line_number", 0)))
    assert actual_leaks_sorted == expected_leaks, f"The extracted leaks do not match the expected findings. Expected: {expected_leaks}, Actual: {actual_leaks_sorted}"
    assert actual_json["leaks"] == expected_leaks, "The 'leaks' list is correct but not sorted by file name and line number ascending as requested."


def test_scanner_executes_on_unseen_inputs():
    """Require the scanner artifact and exercise it against unpredictable scripts."""
    scanner_path = "/home/user/scan_leaks.py"
    scripts_dir = "/home/user/scripts"
    report_path = "/home/user/leak_report.json"
    assert os.path.isfile(scanner_path), f"Scanner is missing at {scanner_path}."

    nonce = secrets.token_hex(8)
    long_password = "long_" + secrets.token_hex(12)
    short_password = "short_" + secrets.token_hex(12)
    first_path = os.path.join(scripts_dir, f"audit_{nonce}_a.sh")
    second_path = os.path.join(scripts_dir, f"audit_{nonce}_z.sh")

    with open(first_path, "w") as f:
        f.write("#!/bin/bash\n")
        f.write("echo harmless\n")
        f.write(f"client --password={long_password} --host random.local\n")
    with open(second_path, "w") as f:
        f.write("#!/bin/bash\n")
        f.write(f"service -p {short_password} --port 9000\n")
        f.write("echo done\n")

    expected_leaks = derive_expected_leaks(scripts_dir)
    if os.path.exists(report_path):
        os.unlink(report_path)

    result = subprocess.run(
        ["python3", scanner_path],
        capture_output=True,
        text=True,
        timeout=15
    )
    assert result.returncode == 0, f"scan_leaks.py failed when executed: {result.stderr}"
    assert os.path.isfile(report_path), "scan_leaks.py did not create /home/user/leak_report.json."

    with open(report_path, "r") as f:
        try:
            actual_json = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("scan_leaks.py generated invalid JSON.")

    assert actual_json == {"leaks": expected_leaks}, (
        f"Scanner output for dynamically added scripts was incorrect. Expected: "
        f"{{'leaks': {expected_leaks}}}, Actual: {actual_json}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
