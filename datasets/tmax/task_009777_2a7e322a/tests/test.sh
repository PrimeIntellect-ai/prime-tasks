#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import secrets
import struct
import subprocess
import tempfile
import pytest

PROJECT_DIR = "/home/user/beacon_parser"
PAYLOAD_PATH = "/home/user/payload.bin"
BINARY_PATH = os.path.join(PROJECT_DIR, "target", "debug", "beacon_parser")


def test_analysis_result_exists():
    result_path = "/home/user/analysis_result.txt"
    assert os.path.isfile(result_path), f"The file {result_path} does not exist."


def test_analysis_result_content():
    result_path = "/home/user/analysis_result.txt"
    if not os.path.isfile(result_path):
        pytest.fail(f"Cannot check content because {result_path} is missing.")

    with open(result_path, "r") as f:
        content = f.read()

    assert "Anomaly detected at frame 423" in content, (
        f"Expected 'Anomaly detected at frame 423' in {result_path}, but it was not found."
    )


def test_rust_code_compiles_and_runs():
    project_dir = PROJECT_DIR
    payload_path = PAYLOAD_PATH

    # Check if we can build
    build_proc = subprocess.run(
        ["cargo", "build"],
        cwd=project_dir,
        capture_output=True,
        text=True
    )
    assert build_proc.returncode == 0, f"Cargo build failed:\n{build_proc.stderr}"

    # Check if we can run without panicking
    run_proc = subprocess.run(
        ["cargo", "run", "--", payload_path],
        cwd=project_dir,
        capture_output=True,
        text=True
    )

    assert run_proc.returncode == 0, f"Parser did not exit cleanly (code 0). Stderr:\n{run_proc.stderr}"
    assert "Anomaly detected at frame 423" in run_proc.stdout, (
        "The parser output did not contain the expected anomaly message when run on the payload."
    )

    with open("/home/user/analysis_result.txt", "r") as f:
        saved_output = f.read()
    assert saved_output == run_proc.stdout, (
        "analysis_result.txt is not the redirected standard output of the current parser run."
    )


def encode_frame(data):
    return b"C2BC" + bytes([1]) + struct.pack("<H", len(data)) + data


def run_binary(payload):
    fd, path = tempfile.mkstemp(prefix="beacon_payload_", suffix=".bin")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(payload)
        proc = subprocess.run(
            [BINARY_PATH, path],
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
            timeout=10,
        )
        return proc
    finally:
        os.unlink(path)


def test_parser_handles_derived_valid_and_malformed_payloads():
    assert os.path.isfile(BINARY_PATH), "cargo build did not produce the parser executable"

    # A fully valid payload must be parsed without inventing an anomaly.
    valid_lengths = [secrets.randbelow(31) for _ in range(3 + secrets.randbelow(6))]
    valid_payload = b"".join(encode_frame(os.urandom(n)) for n in valid_lengths)
    valid_proc = run_binary(valid_payload)
    assert valid_proc.returncode == 0, f"Parser failed on valid input:\n{valid_proc.stderr}"
    assert "Anomaly detected at frame" not in valid_proc.stdout
    for index, length in enumerate(valid_lengths):
        assert f"Parsed frame {index} with length {length}" in valid_proc.stdout

    # Exercise malformed lengths at unpredictable frame indexes and sizes. The
    # expected index is derived from each generated payload, not a fixed oracle.
    for _ in range(8):
        anomaly_index = secrets.randbelow(18)
        normal_lengths = [secrets.randbelow(40) for _ in range(anomaly_index)]
        payload = b"".join(encode_frame(os.urandom(n)) for n in normal_lengths)

        available = secrets.randbelow(12)
        declared = available + 1 + secrets.randbelow(5000)
        payload += b"C2BC" + bytes([secrets.randbelow(256)])
        payload += struct.pack("<H", declared) + os.urandom(available)

        proc = run_binary(payload)
        assert proc.returncode == 0, (
            f"Parser did not exit cleanly for malformed frame {anomaly_index}.\n"
            f"stderr:\n{proc.stderr}"
        )
        expected = f"Anomaly detected at frame {anomaly_index}"
        assert expected in proc.stdout, f"Missing {expected!r}. Output:\n{proc.stdout}"
        assert proc.stdout.count("Anomaly detected at frame") == 1
        assert f"Parsed frame {anomaly_index} with length" not in proc.stdout
        for index, length in enumerate(normal_lengths):
            assert f"Parsed frame {index} with length {length}" in proc.stdout
        assert "panicked at" not in proc.stderr
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
