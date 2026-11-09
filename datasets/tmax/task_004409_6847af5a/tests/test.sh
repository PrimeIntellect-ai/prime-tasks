#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
import time
from pathlib import Path

import pytest

PARSER_SOURCE = Path("/home/user/parser.go")
PARSER_BINARY = Path("/tmp/parser_eval")
RAW_DIR = Path("/home/user/datasets/raw")
PROCESSED_DIR = Path("/home/user/datasets/processed")


def make_dat(dataset_id, payload, declared_length=None, magic=b"RAWD"):
    length = len(payload) if declared_length is None else declared_length
    return magic + struct.pack("<I", dataset_id) + struct.pack("<H", length) + payload


def wait_for_content(path, expected, timeout=8.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if path.read_bytes() == expected:
                return
        except FileNotFoundError:
            pass
        time.sleep(0.1)
    if path.exists():
        pytest.fail(f"{path} had incorrect content: {path.read_bytes()!r}; expected {expected!r}")
    pytest.fail(f"{path} was not created before the timeout")


@pytest.fixture(scope="session", autouse=True)
def build_parser():
    result = subprocess.run(
        ["go", "build", "-o", str(PARSER_BINARY), str(PARSER_SOURCE)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"parser.go does not compile: {result.stderr}"
    assert PARSER_BINARY.is_file() and os.access(PARSER_BINARY, os.X_OK)


def test_parser_go_exists_and_atomic():
    """Test that parser.go exists and uses os.Rename for atomic writes."""
    path = "/home/user/parser.go"
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "os.Rename" in content, "parser.go does not appear to use os.Rename for atomic writes as requested."


def test_watch_sh_exists_and_inotify():
    """Test that watch.sh exists and uses inotifywait."""
    path = "/home/user/watch.sh"
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "inotifywait" in content, "watch.sh does not appear to use inotifywait."


def test_manual_dataset_999():
    """Test that the manually created test file was processed correctly."""
    path = "/home/user/datasets/processed/dataset_999.txt"
    assert os.path.exists(path), f"File {path} does not exist. Did you manually create and process the test file?"
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    assert content == "Test €", f"Content of dataset_999.txt is incorrect. Expected 'Test €', got {repr(content)}."


def test_parser_direct_varied_cp1252_inputs():
    cases = [
        b"",
        b"caf\xe9",
        b"Price \x80 12 \x96 final",
        b"Quotes: \x93hello\x94; \xa3 and \xff",
    ]
    base_id = secrets.randbelow(400_000_000) + 2_000_000_000

    for offset, payload in enumerate(cases):
        dataset_id = base_id + offset
        input_path = Path(f"/tmp/parser_case_{secrets.token_hex(8)}.dat")
        output_path = PROCESSED_DIR / f"dataset_{dataset_id}.txt"
        output_path.unlink(missing_ok=True)
        input_path.write_bytes(make_dat(dataset_id, payload))

        result = subprocess.run(
            [str(PARSER_BINARY), str(input_path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode == 0, result.stderr.decode("utf-8", "replace")
        assert output_path.exists(), f"Parser did not create {output_path}"
        expected = payload.decode("cp1252").encode("utf-8")
        assert output_path.read_bytes() == expected


def test_parser_rejects_bad_magic_and_truncated_payload():
    bad_magic_id = secrets.randbelow(400_000_000) + 2_600_000_000
    truncated_id = bad_magic_id + 1
    cases = [
        (bad_magic_id, make_dat(bad_magic_id, b"bad", magic=b"NOPE")),
        (truncated_id, make_dat(truncated_id, b"abc", declared_length=20)),
    ]

    for dataset_id, data in cases:
        input_path = Path(f"/tmp/parser_bad_{secrets.token_hex(8)}.dat")
        output_path = PROCESSED_DIR / f"dataset_{dataset_id}.txt"
        output_path.unlink(missing_ok=True)
        input_path.write_bytes(data)
        result = subprocess.run(
            [str(PARSER_BINARY), str(input_path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode != 0, "Parser accepted malformed input"
        assert not output_path.exists(), "Parser created output for malformed input"


def test_parser_performs_atomic_rename_from_temporary_file():
    dataset_id = secrets.randbelow(300_000_000) + 3_100_000_000
    payload = b"atomic \x80 payload"
    input_path = Path(f"/tmp/parser_atomic_{secrets.token_hex(8)}.dat")
    final_name = f"dataset_{dataset_id}.txt"
    output_path = PROCESSED_DIR / final_name
    output_path.unlink(missing_ok=True)
    input_path.write_bytes(make_dat(dataset_id, payload))

    monitor = subprocess.Popen(
        ["stdbuf", "-oL", "inotifywait", "-m", "-e", "create,close_write,moved_to", "--format", "%e|%f", str(PROCESSED_DIR)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        time.sleep(0.3)
        result = subprocess.run(
            [str(PARSER_BINARY), str(input_path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode == 0, result.stderr.decode("utf-8", "replace")
        time.sleep(0.3)
    finally:
        monitor.terminate()
        try:
            events, _ = monitor.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            monitor.kill()
            events, _ = monitor.communicate()

    parsed_events = [line.split("|", 1) for line in events.splitlines() if "|" in line]
    assert any("MOVED_TO" in event and name == final_name for event, name in parsed_events), (
        f"Final output was not atomically renamed into place. Events: {events!r}"
    )
    assert any("CREATE" in event and name != final_name for event, name in parsed_events), (
        f"No temporary output file was created in the processed directory. Events: {events!r}"
    )
    assert output_path.read_bytes() == payload.decode("cp1252").encode("utf-8")


def test_watcher_processes_unpredictable_moved_in_file():
    dataset_id = secrets.randbelow(400_000_000) + 1_000_000_000
    payload = b"Watcher \x93" + secrets.token_hex(10).encode("ascii") + b"\x94 costs \x80"
    expected = payload.decode("cp1252").encode("utf-8")
    raw_path = RAW_DIR / f"watch_{secrets.token_hex(10)}.dat"
    staging_path = Path(f"/tmp/{raw_path.name}.staging")
    output_path = PROCESSED_DIR / f"dataset_{dataset_id}.txt"
    output_path.unlink(missing_ok=True)
    staging_path.write_bytes(make_dat(dataset_id, payload))
    os.replace(staging_path, raw_path)
    wait_for_content(output_path, expected)


def test_pipeline_processing():
    """Test the entire pipeline by dropping a valid .dat file and verifying the output."""
    raw_path = "/home/user/datasets/raw/eval_test.dat"
    processed_path = "/home/user/datasets/processed/dataset_42.txt"

    # Binary content: RAWD (52 41 57 44), ID=42 (2A 00 00 00), Length=11 (0B 00), Payload="Hello World"
    test_data = b'\x52\x41\x57\x44\x2A\x00\x00\x00\x0B\x00\x48\x65\x6C\x6C\x6F\x20\x57\x6F\x72\x6C\x64'

    Path(raw_path).unlink(missing_ok=True)
    Path(processed_path).unlink(missing_ok=True)
    with open(raw_path, "wb") as f:
        f.write(test_data)

    # Wait for the background watch script to process it
    wait_for_content(Path(processed_path), b"Hello World")

    assert os.path.exists(processed_path), f"File {processed_path} was not created. Is watch.sh running in the background and processing new files?"

    with open(processed_path, "r", encoding="utf-8") as f:
        content = f.read()

    assert content == "Hello World", f"Content of dataset_42.txt is incorrect. Expected 'Hello World', got {repr(content)}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
