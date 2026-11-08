#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess


def test_recovered_log_exists_and_correct_and_parser_is_fixed():
    bin_path = "/home/user/telemetry.bin"
    script_path = "/home/user/parse_telemetry.py"
    log_path = "/home/user/recovered.log"

    assert os.path.isfile(bin_path), f"Expected binary file {bin_path} to exist."
    assert os.path.isfile(log_path), f"Expected log file {log_path} to exist."
    assert os.path.isfile(script_path), f"Expected parser script {script_path} to exist."

    # Preserve the original verifier's exact check of recovered.log against the binary.
    with open(bin_path, "rb") as f:
        original_data = f.read()

    assert len(original_data) >= 1, "Binary file is empty."

    length = original_data[0]
    assert len(original_data) >= 1 + length + 8, (
        "Binary file is too short to contain the expected payload."
    )

    device_name = original_data[1:1 + length].decode("utf-8")
    val = struct.unpack(">d", original_data[1 + length:1 + length + 8])[0]
    expected_content = f"Device: {device_name}, Value: {val}"

    with open(log_path, "r", encoding="utf-8") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"Content of {log_path} is incorrect.\n"
        f"Expected: '{expected_content}'\n"
        f"Got: '{actual_content}'"
    )

    # Execute the submitted parser on independently generated payloads. This verifies
    # that the off-by-one and double-deserialization bugs were fixed in the script,
    # rather than only producing recovered.log by some separate command.
    token = secrets.token_hex(6)
    generated_value = -((secrets.randbelow(10**12) + 1) / 100000.0)
    cases = [
        (f"Probe-Δ-{token}", generated_value),
        (f"温度-{token}", -0.0),
    ]

    try:
        for name, value in cases:
            name_bytes = name.encode("utf-8")
            assert len(name_bytes) <= 255
            payload = bytes([len(name_bytes)]) + name_bytes + struct.pack(">d", value)
            with open(bin_path, "wb") as f:
                f.write(payload)

            # Derive the expected result from the bytes actually supplied.
            supplied = open(bin_path, "rb").read()
            supplied_length = supplied[0]
            expected_name = supplied[1:1 + supplied_length].decode("utf-8")
            expected_value = struct.unpack(
                ">d", supplied[1 + supplied_length:1 + supplied_length + 8]
            )[0]
            expected_line = f"Device: {expected_name}, Value: {expected_value}"

            result = subprocess.run(
                ["python3", script_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"Parser failed for a valid payload with exit code {result.returncode}.\n"
                f"stderr: {result.stderr}"
            )
            assert result.stdout.splitlines() == [expected_line], (
                "Parser output is incorrect.\n"
                f"Expected exactly: '{expected_line}'\n"
                f"Got stdout: {result.stdout!r}\n"
                f"Got stderr: {result.stderr!r}"
            )
    finally:
        with open(bin_path, "wb") as f:
            f.write(original_data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
