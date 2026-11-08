#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import datetime
import hashlib
import os
import re
import stat
import subprocess
import pytest


def test_compromised_files_list():
    compromised_file = "/home/user/audit/compromised.txt"
    checksum_file = "/home/user/audit/checksums.sha256"
    logs_dir = "/home/user/audit/logs"

    assert os.path.isfile(compromised_file), f"Missing {compromised_file}"
    assert os.path.isfile(checksum_file), f"Missing {checksum_file}"

    with open(compromised_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    # Preserve the original assertion about the expected fixture state.
    expected = ["log2.txt", "log3.txt"]
    assert lines == expected, f"Expected {expected} in compromised.txt, got {lines}"

    # Independently recompute every checksum rather than trusting a hardcoded answer.
    recomputed_failures = []
    with open(checksum_file, "r") as f:
        checksum_lines = [line.rstrip("\n") for line in f if line.strip()]

    assert checksum_lines, f"No checksums found in {checksum_file}"
    for checksum_line in checksum_lines:
        match = re.fullmatch(r"([0-9a-fA-F]{64}) ([ *])(.+)", checksum_line)
        assert match, f"Malformed checksum line: {checksum_line!r}"
        expected_hash, _, listed_name = match.groups()
        listed_path = listed_name if os.path.isabs(listed_name) else os.path.join(logs_dir, listed_name)

        actual_hash = None
        if os.path.isfile(listed_path):
            digest = hashlib.sha256()
            with open(listed_path, "rb") as listed_file:
                for chunk in iter(lambda: listed_file.read(65536), b""):
                    digest.update(chunk)
            actual_hash = digest.hexdigest()

        if actual_hash is None or actual_hash.lower() != expected_hash.lower():
            recomputed_failures.append(os.path.basename(listed_name))

    recomputed_failures.sort()
    assert recomputed_failures == expected, (
        f"Fixture integrity state changed: expected {expected}, got {recomputed_failures}"
    )
    assert lines == recomputed_failures, (
        f"compromised.txt does not match recomputed failures: "
        f"expected {recomputed_failures}, got {lines}"
    )


def test_tls_certificate_and_key():
    cert_file = "/home/user/audit/cert.pem"
    key_file = "/home/user/audit/key.pem"

    assert os.path.isfile(cert_file), f"Missing {cert_file}"
    assert os.path.isfile(key_file), f"Missing {key_file}"

    # Check certificate subject
    subject_cmd = ["openssl", "x509", "-in", cert_file, "-noout", "-subject"]
    result = subprocess.run(subject_cmd, capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read certificate with openssl"
    assert "vulnerable.local" in result.stdout, f"Certificate subject does not contain 'vulnerable.local': {result.stdout}"

    # Check private key validity
    key_cmd = ["openssl", "rsa", "-in", key_file, "-check", "-noout"]
    result = subprocess.run(key_cmd, capture_output=True, text=True)
    assert result.returncode == 0, "Private key is invalid or encrypted with a passphrase"

    # Check if cert and key match
    cert_mod_cmd = ["openssl", "x509", "-in", cert_file, "-noout", "-modulus"]
    key_mod_cmd = ["openssl", "rsa", "-in", key_file, "-noout", "-modulus"]

    cert_mod = subprocess.run(cert_mod_cmd, capture_output=True, text=True).stdout.strip()
    key_mod = subprocess.run(key_mod_cmd, capture_output=True, text=True).stdout.strip()

    assert cert_mod == key_mod, "Certificate and private key do not match"

    # Verify that both the private key and certificate use a 2048-bit RSA key.
    key_text = subprocess.run(
        ["openssl", "pkey", "-in", key_file, "-text", "-noout"],
        capture_output=True,
        text=True,
    )
    assert key_text.returncode == 0, "Failed to inspect private key"
    assert re.search(r"Private-Key:\s*\(2048 bit(?:,|\))", key_text.stdout), (
        "Private key is not 2048 bits"
    )

    cert_text = subprocess.run(
        ["openssl", "x509", "-in", cert_file, "-text", "-noout"],
        capture_output=True,
        text=True,
    )
    assert cert_text.returncode == 0, "Failed to inspect certificate"
    assert re.search(r"Public-Key:\s*\(2048 bit\)", cert_text.stdout), (
        "Certificate public key is not 2048 bits"
    )

    # Verify that the certificate validity interval is exactly 30 days.
    dates = subprocess.run(
        ["openssl", "x509", "-in", cert_file, "-noout", "-dates"],
        capture_output=True,
        text=True,
    )
    assert dates.returncode == 0, "Failed to inspect certificate validity dates"
    parsed_dates = {}
    for line in dates.stdout.splitlines():
        if "=" in line:
            name, value = line.split("=", 1)
            parsed_dates[name] = value

    assert "notBefore" in parsed_dates and "notAfter" in parsed_dates, (
        f"Missing certificate validity dates: {dates.stdout}"
    )
    date_format = "%b %d %H:%M:%S %Y GMT"
    not_before = datetime.datetime.strptime(parsed_dates["notBefore"], date_format)
    not_after = datetime.datetime.strptime(parsed_dates["notAfter"], date_format)
    assert not_after - not_before == datetime.timedelta(days=30), (
        f"Certificate validity is not exactly 30 days: {not_before} to {not_after}"
    )


def test_vulnerability_payload():
    vuln_script = "/home/user/audit/scripts/vuln.sh"
    pwned_file = "/home/user/audit/pwned.txt"

    assert os.path.isfile(vuln_script), f"Missing {vuln_script}"

    # Check permissions are still world-writable
    st = os.stat(vuln_script)
    mode = stat.S_IMODE(st.st_mode)
    assert mode & stat.S_IWOTH, f"{vuln_script} is no longer world-writable"

    # Check original content is preserved
    with open(vuln_script, "r") as f:
        content = f.read()
    assert "Processing data..." in content, "Original content of vuln.sh was overwritten"

    # Clean up pwned.txt if it exists from manual testing
    if os.path.exists(pwned_file):
        os.remove(pwned_file)

    # Execute the script
    result = subprocess.run([vuln_script], capture_output=True, text=True)
    assert result.returncode == 0, f"Execution of {vuln_script} failed"

    # Verify pwned.txt was created and contains correct text
    assert os.path.isfile(pwned_file), f"Payload did not create {pwned_file}"
    with open(pwned_file, "r") as f:
        pwned_content = f.read().strip()

    assert pwned_content == "EXPLOITED", f"Expected 'EXPLOITED' in {pwned_file}, got '{pwned_content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
