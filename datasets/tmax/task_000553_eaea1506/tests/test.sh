#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import struct
import subprocess
import uuid
from pathlib import Path

import pytest

CLEANED_LOGS_PATH = Path("/home/user/cleaned_logs.json")
APP_LOGS_PATH = Path("/home/user/app_logs")
PROJECT_PATH = Path("/home/user/log_processor")


def process_text(text):
    """Recompute the expected text transformation based on the rules."""
    lines = text.split('\n')
    filtered_lines = [line for line in lines if not line.startswith("DEBUG: ")]
    joined = '\n'.join(filtered_lines)
    return re.sub(r'\b(?:\d{1,3}\.){3}\d{1,3}\b', '[REDACTED]', joined)


def test_cleaned_logs_exists():
    assert CLEANED_LOGS_PATH.exists(), f"Output file {CLEANED_LOGS_PATH} is missing."
    assert CLEANED_LOGS_PATH.is_file(), f"Output path {CLEANED_LOGS_PATH} is not a file."


def test_cleaned_logs_content():
    with CLEANED_LOGS_PATH.open("r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {CLEANED_LOGS_PATH} does not contain valid JSON.")

    assert isinstance(data, list), "The JSON root must be an array."
    assert len(data) == 2, f"Expected exactly 2 items in the JSON array, found {len(data)}."

    files_found = {item.get("file"): item.get("contents") for item in data}
    assert "server1/active.dat" not in files_found, "Active file server1/active.dat must be skipped and not included in the JSON."

    log1 = "INFO: User admin logged in from 192.168.1.100\nDEBUG: Connection latency 45ms\nWARN: Disk space low on 10.0.0.5\nINFO: Backup completed"
    log3 = "DEBUG: Init DB\nERROR: Failed to bind to 127.0.0.1\nINFO: Retrying..."
    expected_log1 = process_text(log1)
    expected_log3 = process_text(log3)

    assert "server1/auth.dat" in files_found, "Missing server1/auth.dat in the JSON output."
    assert "server2/deep/db.dat" in files_found, "Missing server2/deep/db.dat in the JSON output."
    assert files_found["server1/auth.dat"] == expected_log1, "Contents for server1/auth.dat do not match expected filtered/redacted text."
    assert files_found["server2/deep/db.dat"] == expected_log3, "Contents for server2/deep/db.dat do not match expected filtered/redacted text."


def write_dat(path, status, payload, trailer=b""):
    path.parent.mkdir(parents=True, exist_ok=True)
    payload_bytes = payload.encode("utf-8")
    path.write_bytes(b"LOG\x00" + b"\x01" + bytes([status]) + struct.pack("<I", len(payload_bytes)) + payload_bytes + trailer)


def derive_expected_from_files():
    expected = {}
    for path in APP_LOGS_PATH.rglob("*.dat"):
        raw = path.read_bytes()
        assert len(raw) >= 10
        assert raw[:4] == b"LOG\x00"
        assert raw[4] == 1
        status = raw[5]
        length = struct.unpack("<I", raw[6:10])[0]
        assert len(raw) >= 10 + length
        if status == 1:
            continue
        assert status == 0
        payload = raw[10:10 + length].decode("utf-8")
        expected[path.relative_to(APP_LOGS_PATH).as_posix()] = process_text(payload)
    return expected


def test_rust_project_processes_actual_binary_files():
    assert PROJECT_PATH.is_dir(), "The Rust project directory /home/user/log_processor is missing."
    assert (PROJECT_PATH / "Cargo.toml").is_file(), "The Rust project is missing Cargo.toml."
    assert any(p.is_file() for p in PROJECT_PATH.rglob("*.rs")), "The project contains no Rust source files."

    shutil.rmtree(APP_LOGS_PATH)
    APP_LOGS_PATH.mkdir(parents=True)

    token = uuid.uuid4().hex
    first = Path("region_" + token[:8]) / "nested" / ("finished_" + token[8:16] + ".dat")
    second = Path("other_" + token[16:24]) / ("audit_" + token[24:] + ".dat")
    third = Path("deep") / token[:6] / token[6:12] / ("tail_" + token[12:18] + ".dat")
    active = Path("active_" + token[18:26]) / ("writing_" + token[26:] + ".dat")

    write_dat(APP_LOGS_PATH / first, 0,
              f"INFO: session {token} from 172.19.4.23\nDEBUG: secret {token}\nWARN: peer 8.8.4.4\n")
    write_dat(APP_LOGS_PATH / second, 0,
              f"DEBUG: remove this {token}\nINFO: retained {token} at 10.23.45.67\n DEBUG: this line remains")
    write_dat(APP_LOGS_PATH / third, 0,
              f"NOTICE: payload {token} uses 192.0.2.44",
              trailer=b"\nDEBUG: TRAILING_BYTES_MUST_NOT_BE_READ\n")
    write_dat(APP_LOGS_PATH / active, 1,
              f"INFO: active bait {token} from 203.0.113.9")
    (APP_LOGS_PATH / "ignored.txt").write_text("not a dat file " + token)

    expected = derive_expected_from_files()
    assert len(expected) == 3

    if CLEANED_LOGS_PATH.exists() or CLEANED_LOGS_PATH.is_symlink():
        CLEANED_LOGS_PATH.unlink()

    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", str(PROJECT_PATH / "Cargo.toml")],
        cwd=str(PROJECT_PATH),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f"Rust program failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert CLEANED_LOGS_PATH.is_file(), "Running the Rust program did not create cleaned_logs.json."

    try:
        data = json.loads(CLEANED_LOGS_PATH.read_text())
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        pytest.fail(f"Rust program produced invalid JSON: {exc}")

    assert isinstance(data, list), "The JSON root produced by the Rust program must be an array."
    assert all(isinstance(item, dict) for item in data), "Every JSON array item must be an object."
    assert all(set(item.keys()) == {"file", "contents"} for item in data), "Each object must have exactly file and contents keys."
    assert all(isinstance(item["file"], str) and isinstance(item["contents"], str) for item in data)
    assert len({item["file"] for item in data}) == len(data), "Output contains duplicate file entries."

    actual = {item["file"]: item["contents"] for item in data}
    assert actual == expected, "Program output does not match results derived from the actual binary files."
    assert active.as_posix() not in actual, "An active file was included in the output."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
