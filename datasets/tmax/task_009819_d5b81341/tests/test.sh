#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import struct
import subprocess
import sys
import tempfile

import pytest


def test_timeline_file():
    timeline_path = "/home/user/timeline.txt"
    assert os.path.isfile(timeline_path), f"Timeline file {timeline_path} does not exist."

    with open(timeline_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {timeline_path}, found {len(lines)}."

    expected_lines = [
        "Ingest | 1715049605 | REQ-042",
        "Transform | 1715049607 | REQ-042",
        "Serialize | 1715049609 | REQ-042"
    ]

    for i, expected in enumerate(expected_lines):
        assert lines[i] == expected, f"Line {i+1} mismatch in timeline.txt. Expected '{expected}', got '{lines[i]}'."


def test_binary_output_file():
    bin_path = "/home/user/data/out_REQ-042.bin"
    assert os.path.isfile(bin_path), f"Output binary file {bin_path} does not exist. Did you run the fixed script on the failing payload?"

    with open(bin_path, "rb") as f:
        data = f.read()

    assert len(data) == 24, f"Binary file should be exactly 24 bytes long, got {len(data)} bytes."

    rec_id, name = struct.unpack('<I20s', data)
    assert rec_id == 42, f"Expected record ID 42, got {rec_id}."

    expected_name = "José".encode('utf-8')
    actual_name = name.rstrip(b'\x00')
    assert actual_name == expected_name, f"Expected name {expected_name} (utf-8 encoded), got {actual_name}."


def test_serializer_script_fixed():
    script_path = "/home/user/app/serializer.py"
    assert os.path.isfile(script_path), f"App file {script_path} is missing."

    with open(script_path, "r") as f:
        content = f.read()

    assert ".encode('ascii')" not in content, "The script still contains the buggy .encode('ascii')."
    assert "utf-8" in content.lower() or "utf8" in content.lower(), "The script does not seem to use utf-8 encoding as requested."


def run_serializer_case(name, record_id):
    script_path = "/home/user/app/serializer.py"
    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = os.path.join(tmpdir, secrets.token_hex(8) + ".json")
        output_path = os.path.join(tmpdir, secrets.token_hex(8) + ".bin")
        with open(input_path, "w", encoding="utf-8") as f:
            json.dump({"user_name": name, "id": record_id}, f, ensure_ascii=False)

        result = subprocess.run(
            [sys.executable, script_path, input_path, output_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )
        assert result.returncode == 0, (
            f"serializer.py failed for Unicode input (exit {result.returncode}): "
            f"{result.stderr.decode('utf-8', errors='replace')}"
        )
        assert os.path.isfile(output_path), "serializer.py did not create the requested output file."
        with open(output_path, "rb") as f:
            actual = f.read()

    encoded = name.encode("utf-8")
    expected = struct.pack("<I20s", record_id, encoded[:20].ljust(20, b"\x00"))
    assert actual == expected, (
        f"Incorrect serialization for {name!r}: expected {expected!r}, got {actual!r}."
    )


def test_serializer_executes_with_additional_unicode_inputs():
    token = secrets.token_hex(6)
    run_serializer_case("Zoë-" + token, secrets.randbelow(2**32))

    # This UTF-8 representation is well over 20 bytes and exercises byte truncation.
    long_name = "国際化-" + secrets.token_hex(12) + "-🙂é"
    assert len(long_name.encode("utf-8")) > 20
    run_serializer_case(long_name, secrets.randbelow(2**32))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
