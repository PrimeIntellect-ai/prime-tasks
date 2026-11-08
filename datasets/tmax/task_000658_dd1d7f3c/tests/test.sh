#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import glob
import re
import stat
import secrets
import subprocess
import pytest

COMMITS_WAL_PATH = "/home/user/backups/processed/commits.wal"
CHUNKS_DIR = "/home/user/backups/processed/chunks"
RAW_LOGS_DIR = "/home/user/backups/raw_logs"
SCRIPT_PATH = "/home/user/process_backups.py"

def get_expected_commits_content():
    """
    Dynamically parses the raw_logs directory to extract, filter, and sort
    the committed transactions as expected by the task.
    """
    wal_files = glob.glob(os.path.join(RAW_LOGS_DIR, "**", "*.wal"), recursive=True)

    transactions = []

    for wal_file in wal_files:
        with open(wal_file, "r", encoding="utf-8") as f:
            lines = f.read().splitlines()

        current_tx = []
        tx_id = None
        for line in lines:
            if "BEGIN TX" in line:
                match = re.search(r"BEGIN TX (\d+)", line)
                if match:
                    tx_id = int(match.group(1))
                current_tx = [line]
            elif "COMMIT TX" in line:
                current_tx.append(line)
                if tx_id is not None:
                    transactions.append((tx_id, "\n".join(current_tx)))
                current_tx = []
                tx_id = None
            elif "ROLLBACK TX" in line:
                current_tx = []
                tx_id = None
            elif current_tx:
                current_tx.append(line)

    # Sort transactions by ID ascending
    transactions.sort(key=lambda x: x[0])

    # Join with a single empty line (\n\n) and ensure it ends with a newline
    if not transactions:
        return b""

    content_str = "\n\n".join(tx[1] for tx in transactions) + "\n"
    return content_str.encode("utf-8")

def assert_chunks_match(expected_content):
    assert os.path.isdir(CHUNKS_DIR), f"Directory missing: {CHUNKS_DIR}"

    expected_chunks = [expected_content[i:i+150] for i in range(0, len(expected_content), 150)]

    # Check that the correct number of chunks exists
    chunk_files = sorted(glob.glob(os.path.join(CHUNKS_DIR, "chunk_*.dat")))
    assert len(chunk_files) == len(expected_chunks), (
        f"Expected {len(expected_chunks)} chunk files, but found {len(chunk_files)}."
    )

    # Verify each chunk's content and naming
    for idx, expected_chunk_data in enumerate(expected_chunks):
        expected_filename = f"chunk_{idx:02d}.dat"
        expected_filepath = os.path.join(CHUNKS_DIR, expected_filename)

        assert os.path.isfile(expected_filepath), f"Expected chunk file missing: {expected_filepath}"

        with open(expected_filepath, "rb") as f:
            actual_chunk_data = f.read()

        assert actual_chunk_data == expected_chunk_data, (
            f"Content mismatch in {expected_filename}. "
            f"Expected {len(expected_chunk_data)} bytes, got {len(actual_chunk_data)} bytes."
        )

def test_script_exists_and_is_regular_file():
    assert os.path.exists(SCRIPT_PATH), f"File missing: {SCRIPT_PATH}"
    assert not os.path.islink(SCRIPT_PATH), f"Script must not be a symbolic link: {SCRIPT_PATH}"
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"Not a regular file: {SCRIPT_PATH}"

def test_commits_wal_content():
    assert os.path.isfile(COMMITS_WAL_PATH), f"File missing: {COMMITS_WAL_PATH}"

    with open(COMMITS_WAL_PATH, "rb") as f:
        actual_content = f.read()

    expected_content = get_expected_commits_content()

    assert actual_content == expected_content, (
        "The contents of commits.wal do not match the expected sorted, "
        "filtered transaction blocks separated by an empty line."
    )

def test_chunks_created_correctly():
    assert os.path.isdir(CHUNKS_DIR), f"Directory missing: {CHUNKS_DIR}"

    expected_content = get_expected_commits_content()
    expected_chunks = [expected_content[i:i+150] for i in range(0, len(expected_content), 150)]

    # Check that the correct number of chunks exists
    chunk_files = sorted(glob.glob(os.path.join(CHUNKS_DIR, "chunk_*.dat")))
    assert len(chunk_files) == len(expected_chunks), (
        f"Expected {len(expected_chunks)} chunk files, but found {len(chunk_files)}."
    )

    # Verify each chunk's content and naming
    for idx, expected_chunk_data in enumerate(expected_chunks):
        expected_filename = f"chunk_{idx:02d}.dat"
        expected_filepath = os.path.join(CHUNKS_DIR, expected_filename)

        assert os.path.isfile(expected_filepath), f"Expected chunk file missing: {expected_filepath}"

        with open(expected_filepath, "rb") as f:
            actual_chunk_data = f.read()

        assert actual_chunk_data == expected_chunk_data, (
            f"Content mismatch in {expected_filename}. "
            f"Expected {len(expected_chunk_data)} bytes, got {len(actual_chunk_data)} bytes."
        )

def test_script_processes_runtime_generated_wal():
    token = secrets.token_hex(24)
    committed_id_1 = 1000000 + secrets.randbelow(1000000)
    committed_id_2 = 3000000 + secrets.randbelow(1000000)
    rolled_back_id = 5000000 + secrets.randbelow(1000000)

    runtime_dir = os.path.join(RAW_LOGS_DIR, "verifier_runtime", token)
    os.makedirs(runtime_dir, exist_ok=True)
    runtime_wal = os.path.join(runtime_dir, "runtime_input.wal")
    with open(runtime_wal, "w", encoding="utf-8", newline="\n") as f:
        f.write(
            f"[2026-09-11T12:00:00] BEGIN TX {committed_id_2}\n"
            f"INSERT INTO runtime_check (value) VALUES ('{token}');\n"
            f"UPDATE runtime_check SET value = '{token}-updated';\n"
            f"[2026-09-11T12:00:02] COMMIT TX {committed_id_2}\n"
            f"[2026-09-11T12:01:00] BEGIN TX {rolled_back_id}\n"
            f"DELETE FROM runtime_check WHERE value = '{token}';\n"
            f"[2026-09-11T12:01:01] ROLLBACK TX {rolled_back_id}\n"
            f"[2026-09-11T12:02:00] BEGIN TX {committed_id_1}\n"
            f"INSERT INTO runtime_check (value) VALUES ('{token}-second');\n"
            f"[2026-09-11T12:02:01] COMMIT TX {committed_id_1}\n"
        )

    expected_content = get_expected_commits_content()

    if os.path.exists(COMMITS_WAL_PATH):
        os.remove(COMMITS_WAL_PATH)
    for chunk_file in glob.glob(os.path.join(CHUNKS_DIR, "chunk_*.dat")):
        if os.path.isfile(chunk_file) or os.path.islink(chunk_file):
            os.remove(chunk_file)

    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Executing {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert os.path.isfile(COMMITS_WAL_PATH), f"File missing after executing script: {COMMITS_WAL_PATH}"
    with open(COMMITS_WAL_PATH, "rb") as f:
        actual_content = f.read()
    assert actual_content == expected_content, (
        "After executing process_backups.py on a runtime-generated WAL, commits.wal "
        "did not contain the expected sorted committed transactions."
    )
    assert token.encode("utf-8") in actual_content
    assert_chunks_match(expected_content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
