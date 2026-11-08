#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import re
import base64
import ipaddress
import subprocess
import tempfile
import pytest

BINARY_PATH = "/home/user/suspicious_web_worker.elf"
CANONICAL_IPS = ["203.0.113.42", "198.51.100.17", "192.0.2.215"]


def extract_malconf_ips():
    assert os.path.isfile(BINARY_PATH), f"Binary {BINARY_PATH} is missing."

    with tempfile.TemporaryDirectory() as tmpdir:
        section_path = os.path.join(tmpdir, "malconf.bin")
        result = subprocess.run(
            ["/usr/bin/objcopy", f"--dump-section=.malconf={section_path}", BINARY_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert result.returncode == 0, (
            f"Could not extract .malconf from {BINARY_PATH}: {result.stderr.strip()}"
        )
        assert os.path.isfile(section_path), "The ELF does not contain an extractable .malconf section."
        with open(section_path, "rb") as f:
            encoded = f.read().rstrip(b"\x00")

    assert encoded, ".malconf is empty."
    assert b"\x00" not in encoded, ".malconf contains unexpected embedded NUL bytes."

    try:
        decoded = base64.b64decode(encoded, validate=True).decode("ascii")
    except Exception as exc:
        pytest.fail(f".malconf is not a valid Base64-encoded ASCII payload: {exc}")

    ips = decoded.split(",")
    assert ips and all(ips), "Decoded .malconf does not contain a comma-separated IP list."
    for ip in ips:
        try:
            ipaddress.ip_address(ip)
        except ValueError:
            pytest.fail(f"Decoded .malconf contains an invalid IP address: {ip}")

    # Preserve the original fixture assertion while deriving all output checks
    # from the actual ELF payload.
    assert set(ips) == set(CANONICAL_IPS), (
        f"Unexpected IPs in the binary's .malconf section: {ips}"
    )
    return ips


def test_block_ips_script():
    expected_ips = extract_malconf_ips()
    script_path = "/home/user/block_ips.sh"
    assert os.path.isfile(script_path), f"File {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"File {script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    assert content.startswith("#!/bin/bash"), f"Script {script_path} does not start with #!/bin/bash."

    for ip in expected_ips:
        pattern = rf"iptables\s+-A\s+INPUT\s+-s\s+{re.escape(ip)}\s+-j\s+DROP"
        assert re.search(pattern, content), f"Script missing or incorrect iptables rule for IP {ip}."


def test_audit_report():
    expected_ips = extract_malconf_ips()
    report_path = "/home/user/audit_report.json"
    assert os.path.isfile(report_path), f"File {report_path} does not exist."

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON.")

    assert os.path.isfile(BINARY_PATH), f"Binary {BINARY_PATH} is missing."
    with open(BINARY_PATH, "rb") as f:
        actual_md5 = hashlib.md5(f.read()).hexdigest()

    assert "elf_md5" in data, "Missing 'elf_md5' in audit report."
    assert data["elf_md5"] == actual_md5, f"Expected MD5 {actual_md5}, got {data['elf_md5']}."

    assert "extracted_ips" in data, "Missing 'extracted_ips' in audit report."
    assert isinstance(data["extracted_ips"], list), "'extracted_ips' must be a list."
    assert set(data["extracted_ips"]) == set(expected_ips), f"Expected IPs {expected_ips}, got {data['extracted_ips']}."

    assert "firewall_script" in data, "Missing 'firewall_script' in audit report."
    assert data["firewall_script"] == "/home/user/block_ips.sh", "Incorrect 'firewall_script' path in audit report."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
