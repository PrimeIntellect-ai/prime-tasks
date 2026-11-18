#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import gzip
import json
import secrets
import stat
import subprocess
import pytest

SOURCE = "/home/user/converter.rs"
BINARY = "/home/user/converter"


def test_converter_artifacts_exist_and_are_rust_buildable():
    assert os.path.isfile(SOURCE), f"Rust source {SOURCE} does not exist."
    assert os.path.isfile(BINARY), f"Compiled converter {BINARY} does not exist."
    mode = os.stat(BINARY).st_mode
    assert mode & stat.S_IXUSR, f"Compiled converter {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} must be a compiled executable."

    result = subprocess.run(
        ["rustc", SOURCE, "-o", "/tmp/converter_from_source"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"converter.rs does not compile with rustc:\n{result.stderr}"


def _exercise_converter(path):
    token = secrets.token_hex(8)
    valid_records = [
        {"level": "INFO", "date": "2024-04-17", "message": f"dynamic message {token}"},
        {"level": "ERROR", "date": "2025-11-03", "message": f"failure code {token} retry 7"},
        {"level": "WARN", "date": "2026-01-29", "message": f"space check {token}"},
    ]
    input_lines = [
        f"[INFO] 2024-04-17 dynamic message {token}",
        "not a valid log line",
        f"[ERROR] 2025-11-03 failure code {token} retry 7",
        "[INFO] 2024-04-17",
        f"INFO 2024-04-17 missing brackets {token}",
        f"[WARN] 20260129 malformed date {token}",
        f"prefix [WARN] 2026-01-29 prefixed {token}",
        f"[WARN] 2026-01-29 space check {token}",
    ]
    result = subprocess.run(
        [path],
        input="\n".join(input_lines) + "\n",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"{path} exited with {result.returncode}: {result.stderr}"

    output_lines = [line for line in result.stdout.splitlines() if line.strip()]
    try:
        records = [json.loads(line) for line in output_lines]
    except json.JSONDecodeError as exc:
        pytest.fail(f"{path} emitted invalid NDJSON: {exc}")
    assert records == valid_records, f"{path} did not correctly convert dynamic input and ignore malformed lines."


def test_submitted_converter_behavior():
    _exercise_converter(BINARY)


def test_rust_source_behavior():
    assert os.path.isfile("/tmp/converter_from_source")
    _exercise_converter("/tmp/converter_from_source")


def test_legacy_logs_deleted():
    dir_path = "/home/user/legacy_logs"
    assert not os.path.exists(dir_path), f"Directory {dir_path} should have been deleted."


def test_processed_logs_directory_exists():
    dir_path = "/home/user/processed_logs"
    assert os.path.isdir(dir_path), f"Directory {dir_path} must exist."


def test_payment_svc_archive():
    file_path = "/home/user/processed_logs/payment_svc_archive.json.gz"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with gzip.open(file_path, 'rt') as f:
        lines = [json.loads(line.strip()) for line in f if line.strip()]

    assert len(lines) == 3, f"Expected 3 valid JSON lines in {file_path}, found {len(lines)}"
    assert lines[0] == {"level": "INFO", "date": "2023-01-01", "message": "Service started"}
    assert lines[1] == {"level": "ERROR", "date": "2023-01-02", "message": "Payment failed for user 123"}
    assert lines[2] == {"level": "WARN", "date": "2023-01-03", "message": "Retry attempt 1"}


def test_auth_svc_archive():
    file_path = "/home/user/processed_logs/auth_svc_archive.json.gz"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with gzip.open(file_path, 'rt') as f:
        lines = [json.loads(line.strip()) for line in f if line.strip()]

    assert len(lines) == 2, f"Expected 2 valid JSON lines in {file_path}, found {len(lines)}"
    assert lines[0] == {"level": "INFO", "date": "2023-02-01", "message": "Auth service boot"}
    assert lines[1] == {"level": "INFO", "date": "2023-02-01", "message": "User admin logged in"}


def test_inventory_svc_archive():
    file_path = "/home/user/processed_logs/inventory_svc_archive.json.gz"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with gzip.open(file_path, 'rt') as f:
        lines = [json.loads(line.strip()) for line in f if line.strip()]

    assert len(lines) == 1, f"Expected 1 valid JSON line in {file_path}, found {len(lines)}"
    assert lines[0] == {"level": "ERROR", "date": "2023-03-05", "message": "Out of stock item 999"}
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
