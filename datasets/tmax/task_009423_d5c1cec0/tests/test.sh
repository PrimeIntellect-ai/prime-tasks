#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import secrets
import struct
import subprocess

PROJECT_DIR = "/home/user/sensor_parser"
CARGO_TOML = os.path.join(PROJECT_DIR, "Cargo.toml")
BINARY = os.path.join(PROJECT_DIR, "target", "release", "sensor_parser")
EXPECTED_LINES = [
    "Timestamp: 1600000050, Payload: aabbccdd",
    "Timestamp: 1600000100, Payload: 1122334455",
    "Timestamp: 1600000200, Payload: ",
]


def test_rust_project_exists():
    """Verify that the Rust project was created in the correct directory."""
    assert os.path.isdir(PROJECT_DIR), f"Rust project directory missing at {PROJECT_DIR}"
    assert os.path.isfile(CARGO_TOML), f"Cargo.toml missing at {CARGO_TOML}"


def test_extracted_log_contents():
    """Verify that the output log file exists and contains the correct extracted records."""
    log_path = "/home/user/extracted_sensor_42.log"
    assert os.path.isfile(log_path), f"Output log file is missing at {log_path}"

    with open(log_path, "r") as f:
        lines = [line.strip("\r\n") for line in f.readlines()]

    if lines and lines[-1] == "":
        lines.pop()

    assert len(lines) == len(EXPECTED_LINES), (
        f"Expected {len(EXPECTED_LINES)} lines, but found {len(lines)} in {log_path}"
    )
    for i, (actual, expected) in enumerate(zip(lines, EXPECTED_LINES)):
        assert actual == expected, (
            f"Line {i+1} mismatch.\nExpected: '{expected}'\nGot:      '{actual}'"
        )


def build_release_binary():
    env = os.environ.copy()
    env["CARGO_HOME"] = "/opt/rust/cargo"
    env["RUSTUP_HOME"] = "/opt/rust/rustup"
    result = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=PROJECT_DIR,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, (
        "cargo build --release failed:\n" + result.stderr.decode("utf-8", "replace")
    )
    assert os.path.isfile(BINARY), f"Release binary missing at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Release binary is not executable: {BINARY}"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Release artifact is not an ELF executable"


def run_parser(compressed_data):
    result = subprocess.run(
        [BINARY],
        cwd=PROJECT_DIR,
        input=compressed_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Parser exited with status {result.returncode}:\n"
        + result.stderr.decode("utf-8", "replace")
    )
    return result.stdout


def test_built_program_on_original_and_generated_streams():
    build_release_binary()

    with open("/home/user/sensor_data.raw.gz", "rb") as f:
        original_output = run_parser(f.read())
    expected_original = ("\n".join(EXPECTED_LINES) + "\n").encode("ascii")
    assert original_output == expected_original, (
        "The built program does not produce the required output for sensor_data.raw.gz"
    )

    records = [
        (17, secrets.randbits(64), secrets.token_bytes(3)),
        (42, (1 << 64) - 1, secrets.token_bytes(257)),
        (256, secrets.randbits(64), secrets.token_bytes(19)),
        (42, secrets.randbits(64), secrets.token_bytes(1)),
        (65535, secrets.randbits(64), secrets.token_bytes(300)),
        (42, 0, b""),
        (7, secrets.randbits(64), secrets.token_bytes(2)),
        (42, secrets.randbits(64), secrets.token_bytes(513)),
    ]

    raw = bytearray()
    expected = bytearray()
    for sensor_id, timestamp, payload in records:
        raw.extend(struct.pack(">4sHQH", b"SENS", sensor_id, timestamp, len(payload)))
        raw.extend(payload)
        if sensor_id == 42:
            expected.extend(
                f"Timestamp: {timestamp}, Payload: {payload.hex()}\n".encode("ascii")
            )

    actual = run_parser(gzip.compress(bytes(raw)))
    assert actual == bytes(expected), (
        "The built program failed on an independently generated gzip stream with "
        "big-endian headers, adjacent records, filtering, or payload formatting"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
