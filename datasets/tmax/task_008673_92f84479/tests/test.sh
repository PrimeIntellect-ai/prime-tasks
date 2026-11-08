#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import shlex
import subprocess
import tempfile


def test_cwe_report():
    report_path = "/home/user/forensics/cwe_report.txt"
    assert os.path.isfile(report_path), f"File not found: {report_path}"

    with open(report_path, "r") as f:
        content = f.read().strip()

    valid_cwes = {"CWE-120", "CWE-121", "CWE-242"}
    assert content in valid_cwes, f"Expected one of {valid_cwes} in {report_path}, but found: '{content}'"
    assert content == "CWE-120", f"Expected CWE-120 for the unbounded strcpy vulnerability, but found: '{content}'"


def test_network_policy_configuration():
    script_path = "/home/user/forensics/block_c2.sh"
    source_path = "/home/user/forensics/attacker_tool.c"
    assert os.path.isfile(script_path), f"File not found: {script_path}"

    with open(script_path, "r") as f:
        content = f.read().strip()

    assert "iptables" in content, f"'iptables' command missing in {script_path}"
    assert "-d 203.0.113.88" in content, f"Destination IP '-d 203.0.113.88' missing in {script_path}"
    assert "-j DROP" in content, f"Action '-j DROP' missing in {script_path}"

    has_append = "-A OUTPUT" in content
    has_insert = "-I OUTPUT" in content
    assert has_append or has_insert, f"Expected '-A OUTPUT' or '-I OUTPUT' in {script_path}"

    with open(source_path, "r") as f:
        source = f.read()
    match = re.search(r'#\s*define\s+C2_SERVER\s+"([^"]+)"', source)
    assert match, f"Could not extract C2 address from {source_path}"
    c2_ip = match.group(1)

    syntax = subprocess.run(["/bin/sh", "-n", script_path], capture_output=True, text=True)
    assert syntax.returncode == 0, f"Invalid shell syntax in {script_path}: {syntax.stderr}"

    tokens = shlex.split(content, comments=True, posix=True)
    assert len(tokens) == 7, f"{script_path} must contain exactly one iptables command"
    assert os.path.basename(tokens[0]) == "iptables", f"Expected an iptables command, found: {tokens[0]}"

    pairs = list(zip(tokens[1::2], tokens[2::2]))
    chain_pairs = [(option, value) for option, value in pairs if option in {"-A", "-I"}]
    destination_pairs = [(option, value) for option, value in pairs if option == "-d"]
    jump_pairs = [(option, value) for option, value in pairs if option == "-j"]
    assert len(chain_pairs) == 1 and chain_pairs[0][1] == "OUTPUT", "Command must target the OUTPUT chain"
    assert destination_pairs == [("-d", c2_ip)], f"Command must target the extracted C2 IP {c2_ip}"
    assert jump_pairs == [("-j", "DROP")], "Command must use the DROP target"
    assert len(chain_pairs) + len(destination_pairs) + len(jump_pairs) == 3, "Unexpected iptables arguments or additional commands found"


def test_sensitive_data_redaction():
    forensics_dir = "/home/user/forensics"
    source_path = os.path.join(forensics_dir, "redact.c")
    stolen_path = os.path.join(forensics_dir, "stolen_data.txt")
    redacted_path = os.path.join(forensics_dir, "redacted_data.txt")

    assert os.path.isfile(redacted_path), f"File not found: {redacted_path}"

    expected_content = (
        "John Doe, dob: 1980-01-01, ssn: 123-45-REDACTED, balance: $5000\n"
        "Jane Smith, dob: 1992-05-15, ssn: 987-65-REDACTED, balance: $12000\n"
        "System Admin, notes: \"Call the bank about 000-11-REDACTED tomorrow.\"\n"
    )

    with open(redacted_path, "r") as f:
        content = f.read()

    assert content.strip() == expected_content.strip(), f"Content of {redacted_path} does not match the expected redacted output."
    assert os.path.isfile(source_path), f"File not found: {source_path}"

    with tempfile.TemporaryDirectory() as temp_dir:
        executable = os.path.join(temp_dir, "redact")
        compilation = subprocess.run(
            ["gcc", "-std=c11", "-O2", source_path, "-o", executable],
            capture_output=True,
            text=True,
        )
        assert compilation.returncode == 0, f"Could not compile {source_path}: {compilation.stderr}"
        assert os.path.isfile(executable) and os.access(executable, os.X_OK), "Compiled redaction program is not executable"

        values = [
            f"{secrets.randbelow(1000):03d}-{secrets.randbelow(100):02d}-{secrets.randbelow(10000):04d}"
            for _ in range(4)
        ]
        nonce = secrets.token_hex(12)
        dynamic_input = (
            f"case {nonce}: {values[0]} and {values[1]} remain on this line\n"
            f"punctuation=[{values[2]}], quoted='{values[3]}'\n"
            "unchanged decoys: 12-345-6789, 123-4-5678, 123-45-67890 and plain text\n"
        )
        expected_dynamic = re.sub(
            r"(?<!\d)(\d{3}-\d{2})-\d{4}(?!\d)",
            r"\1-REDACTED",
            dynamic_input,
        )

        with open(stolen_path, "rb") as f:
            original_stolen = f.read()
        original_redacted_exists = os.path.exists(redacted_path)
        original_redacted = None
        if original_redacted_exists:
            with open(redacted_path, "rb") as f:
                original_redacted = f.read()

        try:
            with open(stolen_path, "w") as f:
                f.write(dynamic_input)
            if os.path.exists(redacted_path):
                os.unlink(redacted_path)

            execution = subprocess.run(
                [executable],
                cwd=forensics_dir,
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert execution.returncode == 0, f"Redaction program failed: {execution.stderr}"
            assert os.path.isfile(redacted_path), "Redaction program did not generate redacted_data.txt"
            with open(redacted_path, "r") as f:
                actual_dynamic = f.read()
            assert actual_dynamic == expected_dynamic, "Redaction program failed generated-input behavioral testing"
        finally:
            with open(stolen_path, "wb") as f:
                f.write(original_stolen)
            if original_redacted_exists:
                with open(redacted_path, "wb") as f:
                    f.write(original_redacted)
            elif os.path.exists(redacted_path):
                os.unlink(redacted_path)


def test_cryptographic_hashing():
    payload_path = "/home/user/forensics/malware_payload.bin"
    report_path = "/home/user/forensics/hash_report.txt"

    assert os.path.isfile(payload_path), f"File not found: {payload_path}"
    assert os.path.isfile(report_path), f"File not found: {report_path}"

    with open(payload_path, "rb") as f:
        expected_hash = hashlib.sha256(f.read()).hexdigest()

    with open(report_path, "r") as f:
        content = f.read().strip()

    pattern = rf"^SHA256:\s*{expected_hash}$"
    assert re.match(pattern, content, re.IGNORECASE), f"Content of {report_path} ('{content}') does not match expected format 'SHA256: {expected_hash}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
