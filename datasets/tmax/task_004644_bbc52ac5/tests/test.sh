#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import json
import os
import random
import re
import subprocess
import uuid

import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

SCRIPT_PATH = "/home/user/analyze_agent.py"
BINARY_PATH = "/home/user/audit_agent"
LOG_PATH = "/home/user/audit_trail.log"


def extract_expected(binary_path):
    with open(binary_path, "rb") as f:
        data = f.read()

    assert data.startswith(b"\x7fELF"), f"{binary_path} is not an ELF binary."

    ip_match = re.search(rb"TARGET_IP=((?:\d{1,3}\.){3}\d{1,3})", data)
    assert ip_match is not None, "TARGET_IP marker was not found in the ELF."
    ip = ip_match.group(1).decode("ascii")
    assert all(0 <= int(part) <= 255 for part in ip.split(".")), "Embedded IP is invalid."

    cert_match = re.search(
        rb"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----",
        data,
        re.DOTALL,
    )
    assert cert_match is not None, "Embedded PEM certificate was not found in the ELF."
    cert = x509.load_pem_x509_certificate(cert_match.group(0) + b"\n")
    cn_values = cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)
    assert cn_values, "Embedded certificate has no Subject Common Name."

    expiry_value = getattr(cert, "not_valid_after_utc", None)
    if expiry_value is None:
        expiry_value = cert.not_valid_after
    expiry = expiry_value.strftime("%Y-%m-%d %H:%M:%S")
    return ip, cn_values[0].value, expiry


def expected_lines(binary_path):
    ip, cn, expiry = extract_expected(binary_path)
    return [
        f"[AUDIT] Embedded IP: {ip}",
        f"[AUDIT] Cert Subject: {cn}",
        f"[AUDIT] Cert Expiry: {expiry}",
        f"[AUDIT] Block Command: iptables -A OUTPUT -d {ip} -j DROP",
    ]


def run_analyzer():
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"analyze_agent.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(LOG_PATH), "The analyzer did not create audit_trail.log."


def test_analyze_agent_script_exists():
    """Test that the python script analyze_agent.py exists."""
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."


def test_analyzer_executes_successfully():
    """Run the submitted analyzer rather than accepting a pre-created log."""
    run_analyzer()


def test_audit_trail_log_exists():
    """Test that the audit_trail.log file exists."""
    assert os.path.exists(LOG_PATH), f"The log file {LOG_PATH} does not exist."
    assert os.path.isfile(LOG_PATH), f"{LOG_PATH} is not a file."


def test_audit_trail_log_content():
    """Test that the audit_trail.log contains the correct extracted information."""
    with open(LOG_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original fixed assertions.
    expected_ip_line = "[AUDIT] Embedded IP: 203.0.113.85"
    expected_subject_line = "[AUDIT] Cert Subject: legacy-audit.local"
    expected_block_line = "[AUDIT] Block Command: iptables -A OUTPUT -d 203.0.113.85 -j DROP"

    assert expected_ip_line in content, f"Expected line '{expected_ip_line}' not found in {LOG_PATH}."
    assert expected_subject_line in content, f"Expected line '{expected_subject_line}' not found in {LOG_PATH}."
    assert expected_block_line in content, f"Expected line '{expected_block_line}' not found in {LOG_PATH}."

    expiry_pattern = r"\[AUDIT\] Cert Expiry: \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}"
    assert re.search(expiry_pattern, content) is not None, (
        f"Expected expiry date line matching pattern '{expiry_pattern}' not found in {LOG_PATH}."
    )

    # Derive all values, including expiry, from the actual ELF and require the report format.
    assert content.splitlines() == expected_lines(BINARY_PATH)


def test_analyzer_handles_values_extracted_from_a_different_elf():
    """Reject scripts that merely print the known values instead of analyzing the ELF."""
    with open(BINARY_PATH, "rb") as f:
        original_binary = f.read()
    original_mode = os.stat(BINARY_PATH).st_mode

    probe_ip = f"198.51.100.{random.SystemRandom().randint(1, 254)}"
    probe_cn = f"probe-{uuid.uuid4().hex}.local"
    now = datetime.datetime.utcnow().replace(microsecond=0)
    probe_expiry = now + datetime.timedelta(
        days=random.SystemRandom().randint(500, 2500),
        seconds=random.SystemRandom().randint(0, 80000),
    )

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = issuer = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, probe_cn)])
    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(days=1))
        .not_valid_after(probe_expiry)
        .sign(key, hashes.SHA256())
    )
    cert_pem = cert.public_bytes(serialization.Encoding.PEM).decode("ascii")

    source_path = "/tmp/audit_agent_probe.c"
    probe_path = "/tmp/audit_agent_probe"
    source = (
        "#include <stdio.h>\n"
        f"const char embedded_cert[] = {json.dumps(cert_pem)};\n"
        f"const char target_ip[] = {json.dumps('TARGET_IP=' + probe_ip)};\n"
        "int main(void) { return (embedded_cert[0] == 0 || target_ip[0] == 0); }\n"
    )
    with open(source_path, "w", encoding="utf-8") as f:
        f.write(source)
    subprocess.run(["gcc", "-O0", source_path, "-o", probe_path], check=True, timeout=30)

    try:
        with open(probe_path, "rb") as f:
            probe_binary = f.read()
        with open(BINARY_PATH, "wb") as f:
            f.write(probe_binary)
        os.chmod(BINARY_PATH, original_mode)

        run_analyzer()
        with open(LOG_PATH, "r", encoding="utf-8") as f:
            probe_content = f.read()
        assert probe_content.splitlines() == expected_lines(BINARY_PATH)
    finally:
        with open(BINARY_PATH, "wb") as f:
            f.write(original_binary)
        os.chmod(BINARY_PATH, original_mode)
        subprocess.run(
            ["python3", SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=30,
            check=False,
        )
        for path in (source_path, probe_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
