#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import base64
import gzip
import secrets
import subprocess
import sys

from cryptography import x509
from cryptography.x509.oid import NameOID


def expected_c2_info():
    cert_path = "/home/user/incident_data/c2_certificate.pem"
    dns_path = "/home/user/incident_data/local_dns.json"

    assert os.path.isfile(cert_path), f"The file {cert_path} is missing."
    assert os.path.isfile(dns_path), f"The file {dns_path} is missing."

    with open(cert_path, "rb") as f:
        cert = x509.load_pem_x509_certificate(f.read())

    cn_attributes = cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)
    assert cn_attributes, "The certificate subject does not contain a Common Name."
    cn = cn_attributes[0].value

    with open(dns_path, "r") as f:
        dns_records = json.load(f)

    assert cn in dns_records, f"The certificate CN '{cn}' is missing from local_dns.json."
    return cn, dns_records[cn]


def test_analysis_directory_exists():
    """Verify that the analysis directory was created."""
    assert os.path.isdir("/home/user/analysis"), "The directory /home/user/analysis/ was not created."


def test_malware_py_decoded_correctly():
    """Verify that the malware payload was correctly decoded and decompressed."""
    malware_path = "/home/user/analysis/malware.py"
    payload_path = "/home/user/incident_data/intercepted_payload.txt"

    assert os.path.isfile(malware_path), f"The file {malware_path} is missing."
    assert os.path.isfile(payload_path), f"The file {payload_path} is missing."

    with open(payload_path, "r") as f:
        b64_payload = f.read().strip()

    compressed_payload = base64.b64decode(b64_payload)
    expected_malware_content = gzip.decompress(compressed_payload).decode("utf-8")

    with open(malware_path, "r") as f:
        actual_malware_content = f.read()

    assert actual_malware_content == expected_malware_content, "The content of malware.py does not match the decoded payload."


def test_cwe_identification():
    """Verify that the correct CWE was identified."""
    cwe_path = "/home/user/analysis/cwe.txt"
    assert os.path.isfile(cwe_path), f"The file {cwe_path} is missing."

    with open(cwe_path, "r") as f:
        cwe_content = f.read().strip()

    assert cwe_content == "CWE-78", f"Expected CWE-78, but found '{cwe_content}' in {cwe_path}."


def test_c2_info_extraction():
    """Verify that the C2 info was extracted from the certificate and DNS data."""
    c2_info_path = "/home/user/analysis/c2_info.txt"
    assert os.path.isfile(c2_info_path), f"The file {c2_info_path} is missing."

    with open(c2_info_path, "r") as f:
        c2_info_content = f.read().strip()

    cn, ip = expected_c2_info()
    expected_content = f"{cn},{ip}"
    assert c2_info_content == expected_content, f"Expected '{expected_content}', but found '{c2_info_content}' in {c2_info_path}."


def test_firewall_rule_generation():
    """Verify that the saved firewall rule matches the dynamically derived C2 IP."""
    fw_rules_path = "/home/user/analysis/firewall.rules"
    assert os.path.isfile(fw_rules_path), f"The file {fw_rules_path} is missing."

    with open(fw_rules_path, "r") as f:
        fw_rules_content = f.read().strip()

    _, ip = expected_c2_info()
    expected_rule = f"iptables -A OUTPUT -d {ip} -j DROP"
    assert fw_rules_content == expected_rule, f"Expected '{expected_rule}', but found '{fw_rules_content}' in {fw_rules_path}."


def test_generator_exists_and_dynamically_reads_c2_info():
    """Execute generate_fw.py against a fresh C2 input and verify its generated rule."""
    generator_path = "/home/user/generate_fw.py"
    c2_info_path = "/home/user/analysis/c2_info.txt"
    fw_rules_path = "/home/user/analysis/firewall.rules"

    assert os.path.isfile(generator_path), f"The file {generator_path} is missing or is not a regular file."

    with open(generator_path, "rb") as f:
        compile(f.read(), generator_path, "exec")

    original_c2 = open(c2_info_path, "rb").read()
    original_fw = open(fw_rules_path, "rb").read() if os.path.isfile(fw_rules_path) else None
    test_ip = f"203.0.113.{secrets.randbelow(253) + 1}"
    expected_rule = f"iptables -A OUTPUT -d {test_ip} -j DROP"

    try:
        with open(c2_info_path, "w") as f:
            f.write(f"dynamic-test.invalid,{test_ip}\n")
        if os.path.exists(fw_rules_path):
            os.remove(fw_rules_path)

        result = subprocess.run(
            [sys.executable, generator_path],
            cwd="/home/user",
            text=True,
            capture_output=True,
            timeout=10,
        )
        generated_file = None
        if os.path.isfile(fw_rules_path):
            with open(fw_rules_path, "r") as f:
                generated_file = f.read().strip()
    finally:
        with open(c2_info_path, "wb") as f:
            f.write(original_c2)
        if original_fw is None:
            if os.path.exists(fw_rules_path):
                os.remove(fw_rules_path)
        else:
            with open(fw_rules_path, "wb") as f:
                f.write(original_fw)

    assert result.returncode == 0, f"generate_fw.py failed: {result.stderr}"
    generated_stdout = result.stdout.strip()
    assert expected_rule in (generated_stdout, generated_file), (
        "generate_fw.py did not dynamically generate the expected rule from c2_info.txt. "
        f"Expected '{expected_rule}', stdout was '{generated_stdout}', and firewall.rules was '{generated_file}'."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
