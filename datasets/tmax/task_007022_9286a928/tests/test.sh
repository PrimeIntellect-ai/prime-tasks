#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import stat
import subprocess
import tempfile


def get_derived_truth():
    """Derive the expected report from the supplied logs and hashes."""
    log_path = "/home/user/pentest_data/access.log"
    hashes_path = "/home/user/pentest_data/malicious_hashes.txt"

    assert os.path.exists(log_path), f"Missing log file: {log_path}"
    assert os.path.exists(hashes_path), f"Missing hashes file: {hashes_path}"

    with open(hashes_path, "r") as f:
        known_hashes = {line.strip() for line in f if line.strip()}

    matching_ip = None
    matching_payload = None

    with open(log_path, "r") as f:
        for line in f:
            match = re.search(r'^(\S+).*/api/auth\?payload=([0-9a-fA-F]+)', line)
            if match:
                ip = match.group(1)
                hex_payload = match.group(2)
                raw_bytes = bytes.fromhex(hex_payload)
                decoded_str = "".join(chr(b ^ 0x7F) for b in raw_bytes)
                payload_hash = hashlib.sha256(decoded_str.encode("utf-8")).hexdigest()

                if payload_hash in known_hashes:
                    matching_ip = ip
                    matching_payload = decoded_str
                    break

    assert matching_ip is not None and matching_payload is not None, \
        "Could not derive truth from provided data files."
    return matching_ip, matching_payload


def decoder_cases():
    inputs = ["", "00", "00010203", "7f", "00112233445566778899aabbccddeeff"]

    with open("/home/user/pentest_data/access.log", "r") as f:
        for line in f:
            match = re.search(r'/api/auth\?payload=([0-9a-fA-F]+)', line)
            if match:
                inputs.append(match.group(1))

    # Unpredictable cases prevent an executable from merely special-casing fixture data.
    for size in (2, 7, 19, 64):
        inputs.append(os.urandom(size).hex())

    return [(hex_value, bytes(b ^ 0x7F for b in bytes.fromhex(hex_value)))
            for hex_value in inputs]


def assert_decoder_works(path, cases):
    for hex_value, expected in cases:
        result = subprocess.run(
            [path, hex_value],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            check=False,
        )
        assert result.returncode == 0, \
            f"Decoder {path} failed for a {len(hex_value) // 2}-byte payload"
        assert result.stdout == expected, \
            f"Decoder {path} did not decode the entire payload correctly"
        assert result.stderr == b"", f"Decoder {path} produced unexpected diagnostic output"


def test_decoder_cpp_fixed():
    """Validate that the source no longer contains the recovered loop bug."""
    cpp_path = "/home/user/pentest_data/decoder.cpp"
    assert os.path.exists(cpp_path), f"Missing decoder source file: {cpp_path}"

    with open(cpp_path, "r") as f:
        content = f.read()

    normalized = re.sub(r"\s+", "", content)
    assert "length()/4" not in normalized, \
        "The C++ decoder still contains the 'length() / 4' bug."


def test_decoder_compiled():
    """Execute both the submitted binary and a fresh build of the repaired source."""
    cpp_path = "/home/user/pentest_data/decoder.cpp"
    bin_path = "/home/user/pentest_data/decoder"

    assert os.path.exists(bin_path), f"Compiled decoder binary not found at {bin_path}"
    assert os.path.isfile(bin_path), f"File at {bin_path} is not a regular file."
    assert stat.S_ISREG(os.stat(bin_path).st_mode), f"File at {bin_path} is not a regular file."
    assert os.access(bin_path, os.X_OK), f"File at {bin_path} is not executable."

    with open(bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File at {bin_path} is not a compiled ELF binary."

    cases = decoder_cases()
    assert_decoder_works(bin_path, cases)

    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "decoder")
        build = subprocess.run(
            ["g++", cpp_path, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            check=False,
        )
        assert build.returncode == 0, \
            f"Repaired decoder.cpp does not compile: {build.stderr.decode(errors='replace')}"
        assert_decoder_works(rebuilt, cases)


def test_report_content_matches_truth():
    """Validate that the final report contains the derived IP and payload."""
    report_path = "/home/user/report.txt"
    assert os.path.exists(report_path), f"Final report not found at {report_path}"

    expected_ip, expected_payload = get_derived_truth()

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, \
        f"Report should contain exactly two non-empty lines, found {len(lines)}."

    ip_line = lines[0]
    payload_line = lines[1]

    assert ip_line.startswith("IP: "), "First line of report must start with 'IP: '"
    assert payload_line.startswith("Payload: "), \
        "Second line of report must start with 'Payload: '"

    actual_ip = ip_line.split("IP: ")[1].strip()
    actual_payload = payload_line.split("Payload: ")[1].strip()

    assert actual_ip == expected_ip, \
        f"Reported IP '{actual_ip}' does not match the expected IP '{expected_ip}'."
    assert actual_payload == expected_payload, \
        f"Reported Payload '{actual_payload}' does not match the expected Payload '{expected_payload}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
