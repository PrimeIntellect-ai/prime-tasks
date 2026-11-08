#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from pathlib import Path

import pytest

SOURCE_FILE = "/home/user/decode_rle.rs"
EXECUTABLE_FILE = "/home/user/decode_rle"


def test_rust_files_exist():
    """Check if the Rust source file and compiled executable exist."""
    assert os.path.isfile(SOURCE_FILE), f"Rust source file {SOURCE_FILE} is missing."
    assert os.path.isfile(EXECUTABLE_FILE), f"Compiled executable {EXECUTABLE_FILE} is missing."
    assert os.access(EXECUTABLE_FILE, os.X_OK), f"File {EXECUTABLE_FILE} is not executable."

    with open(EXECUTABLE_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE_FILE} is not a compiled ELF executable."


def test_oom_events_content():
    """Check if the oom_events.log contains the correct sorted output."""
    log_file = "/home/user/oom_events.log"
    assert os.path.isfile(log_file), f"Log file {log_file} is missing."

    expected_lines = [
        "CRITICAL_OOM: postgresql process terminated\n",
        "CRITICAL_OOM: redis cache memory limit exceeded\n",
        "CRITICAL_OOM: worker thread out of memory\n"
    ]

    with open(log_file, "r") as f:
        actual_lines = f.readlines()

    assert actual_lines == expected_lines, (
        f"Content of {log_file} does not match expected output.\n"
        f"Expected:\n{''.join(expected_lines)}\n"
        f"Actual:\n{''.join(actual_lines)}"
    )


def test_symlink():
    """Check if the latest_incident symlink is correctly created."""
    symlink_path = "/home/user/latest_incident"
    target_path = "/home/user/oom_events.log"

    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."

    actual_target = os.readlink(symlink_path)
    if not os.path.isabs(actual_target):
        actual_target = os.path.normpath(os.path.join(os.path.dirname(symlink_path), actual_target))

    assert actual_target == target_path, (
        f"Symlink {symlink_path} points to {actual_target} instead of {target_path}."
    )


@pytest.fixture(scope="session")
def rebuilt_decoder(tmp_path_factory):
    """Compile the submitted Rust source independently for behavioral testing."""
    output = tmp_path_factory.mktemp("rebuilt") / "decode_rle_from_source"
    result = subprocess.run(
        ["rustc", SOURCE_FILE, "-o", str(output)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        "Submitted Rust source does not compile:\n" + result.stderr.decode("utf-8", errors="replace")
    )
    return str(output)


def run_decoder(executable, input_path):
    result = subprocess.run(
        [executable, str(input_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"Decoder {executable} exited with {result.returncode}:\n"
        + result.stderr.decode("utf-8", errors="replace")
    )
    return result.stdout


def test_decoders_on_novel_rle(tmp_path, rebuilt_decoder):
    """Exercise both the delivered binary and freshly compiled source on novel RLE data."""
    alphabet = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 :_-/\n"
    pairs = [(255, ord("Z")), (3, ord("\n")), (1, ord("!"))]
    for _ in range(24):
        pairs.append((1 + secrets.randbelow(31), alphabet[secrets.randbelow(len(alphabet))]))

    encoded = bytes(value for count, char in pairs for value in (count, char))
    expected = b"".join(bytes([char]) * count for count, char in pairs)
    fixture = tmp_path / "novel fixture.rle"
    fixture.write_bytes(encoded)

    for executable in (EXECUTABLE_FILE, rebuilt_decoder):
        assert run_decoder(executable, fixture) == expected, (
            f"Decoder {executable} did not correctly decode a novel RLE fixture."
        )


def decode_expected(data):
    assert len(data) % 2 == 0
    return b"".join(bytes([data[i + 1]]) * data[i] for i in range(0, len(data), 2))


def test_delivered_decoder_processes_storage_files():
    """Derive expected data from every stored RLE file and compare it with the decoder and log."""
    matching_lines = []
    paths = sorted(Path("/home/user/storage_logs").rglob("*.rle"))
    assert paths, "No .rle files were found under /home/user/storage_logs/."

    for path in paths:
        expected = decode_expected(path.read_bytes())
        actual = run_decoder(EXECUTABLE_FILE, path)
        assert actual == expected, f"Decoder output is incorrect for {path}."
        for line in expected.decode("ascii").splitlines():
            if "CRITICAL_OOM" in line:
                matching_lines.append(line + "\n")

    with open("/home/user/oom_events.log", "r", encoding="ascii") as f:
        actual_log = f.readlines()
    assert actual_log == sorted(matching_lines), (
        "oom_events.log does not equal the sorted CRITICAL_OOM lines derived from all .rle files."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
