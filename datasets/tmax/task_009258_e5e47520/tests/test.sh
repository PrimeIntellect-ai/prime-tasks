#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import secrets
import struct
import subprocess
import sys
import tempfile


def test_recovered_bin():
    """Verify that the recovered binary log is carved correctly."""
    path = "/home/user/recovered.bin"
    assert os.path.isfile(path), f"Missing file: {path}"

    # Reconstruct the expected binary log based on the setup
    log_magic = b'LOG\x00'
    rec1 = struct.pack('>HH', 0, 4) + b'JUNK'
    rec2 = struct.pack('>HH', 1, 22) + b'FLAG{R3C0V3R3D_P4RS3D}'
    terminator = b'\xff\xff\xff\xff'
    expected_binary_log = log_magic + rec1 + rec2 + terminator

    with open(path, 'rb') as f:
        data = f.read()

    assert data == expected_binary_log, f"The contents of {path} do not exactly match the expected carved binary log."


def test_flag_txt():
    """Verify that the flag was successfully extracted and saved."""
    path = "/home/user/flag.txt"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, 'r') as f:
        content = f.read().strip()

    expected_flag = "FLAG{R3C0V3R3D_P4RS3D}"
    assert content == expected_flag, f"The contents of {path} are incorrect. Expected '{expected_flag}', got '{content}'."


def run_parser(log_path):
    parser_path = "/home/user/parser.py"
    assert os.path.isfile(parser_path), f"Missing parser: {parser_path}"
    result = subprocess.run(
        [sys.executable, parser_path, log_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"parser.py crashed or returned an error for {log_path}: "
        f"{result.stderr.decode('utf-8', errors='replace')}"
    )
    return result.stdout.decode('utf-8')


def test_patched_parser_executes_and_handles_malformed_record():
    """Execute the submitted parser and verify it skips version-zero records."""
    recovered_output = run_parser("/home/user/recovered.bin")
    assert recovered_output.splitlines() == ["FLAG{R3C0V3R3D_P4RS3D}"], (
        "parser.py did not print exactly the valid payload from recovered.bin"
    )

    malformed_payload = ("BAD_" + secrets.token_hex(9)).encode('ascii')
    valid_payloads = [
        ("DATA_" + secrets.token_hex(12)).encode('ascii'),
        ("MORE_" + secrets.token_hex(10)).encode('ascii'),
    ]
    synthetic_log = bytearray(b'LOG\x00')
    synthetic_log += struct.pack('>HH', 0, len(malformed_payload)) + malformed_payload
    synthetic_log += struct.pack('>HH', 1, len(valid_payloads[0])) + valid_payloads[0]
    synthetic_log += struct.pack('>HH', 2, len(valid_payloads[1])) + valid_payloads[1]
    synthetic_log += b'\xff\xff\xff\xff'

    with tempfile.NamedTemporaryFile(prefix="parser-edge-", suffix=".bin") as tmp:
        tmp.write(synthetic_log)
        tmp.flush()
        output = run_parser(tmp.name)

    expected_lines = [payload.decode('ascii') for payload in valid_payloads]
    assert output.splitlines() == expected_lines, (
        "parser.py must ignore the malformed version-zero record and print all "
        "subsequent valid payloads"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
