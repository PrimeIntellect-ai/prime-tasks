#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import secrets
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/sanitize.py"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"
EVIL_CORPUS_DIR = "/app/corpus/evil/"


def run_script_on_file(filepath):
    result = subprocess.run(
        ["python3", SCRIPT_PATH, filepath],
        capture_output=True,
        text=True
    )
    return result.stdout.strip().split('\n')


def count_lines(filepath):
    with open(filepath, 'r') as f:
        return sum(1 for line in f if line.strip())


def test_sanitize_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable."
    with open(SCRIPT_PATH, "rb") as f:
        first_line = f.readline()
    assert first_line.startswith(b"#!") and b"python3" in first_line, \
        f"{SCRIPT_PATH} must be an executable Python 3 script."


def test_clean_corpus():
    clean_files = [f for f in glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*")) if os.path.isfile(f)]
    assert len(clean_files) > 0, f"No files found in {CLEAN_CORPUS_DIR}"

    total_clean_lines = 0
    modified_clean_lines = 0
    offending_files = []

    for filepath in clean_files:
        lines_in_file = count_lines(filepath)
        if lines_in_file == 0:
            continue

        total_clean_lines += lines_in_file

        output_lines = run_script_on_file(filepath)
        output_lines = [line.strip() for line in output_lines if line.strip()]

        assert len(output_lines) == lines_in_file, f"Output length mismatch for {filepath}. Expected {lines_in_file} lines, got {len(output_lines)}."

        bad_count = sum(1 for out in output_lines if out != "CLEAN")
        if bad_count > 0:
            modified_clean_lines += bad_count
            offending_files.append(os.path.basename(filepath))

    if modified_clean_lines > 0:
        pytest.fail(f"{modified_clean_lines} of {total_clean_lines} clean modified. Offending files: {', '.join(set(offending_files))}")


def test_evil_corpus():
    evil_files = [f for f in glob.glob(os.path.join(EVIL_CORPUS_DIR, "*")) if os.path.isfile(f)]
    assert len(evil_files) > 0, f"No files found in {EVIL_CORPUS_DIR}"

    total_evil_lines = 0
    bypassed_evil_lines = 0
    offending_files = []

    for filepath in evil_files:
        lines_in_file = count_lines(filepath)
        if lines_in_file == 0:
            continue

        total_evil_lines += lines_in_file

        output_lines = run_script_on_file(filepath)
        output_lines = [line.strip() for line in output_lines if line.strip()]

        assert len(output_lines) == lines_in_file, f"Output length mismatch for {filepath}. Expected {lines_in_file} lines, got {len(output_lines)}."

        bad_count = sum(1 for out in output_lines if out != "EVIL")
        if bad_count > 0:
            bypassed_evil_lines += bad_count
            offending_files.append(os.path.basename(filepath))

    if bypassed_evil_lines > 0:
        pytest.fail(f"{bypassed_evil_lines} of {total_evil_lines} evil bypassed. Offending files: {', '.join(set(offending_files))}")


def test_randomized_mixed_unlabelled_file():
    rng = random.Random(secrets.randbits(256))
    cases = []

    for _ in range(80):
        uid = rng.randint(1000, 9999)
        ts = rng.randint(1500000000, 2100000000)
        ts += (1 - ts) % 7
        clean = {"user_id": uid, "timestamp": ts, "event": "data_processed"}
        cases.append((json.dumps(clean), "CLEAN"))

        original_uid = rng.randint(1000, 9999)
        evil_ts = rng.randint(1500000000, 2100000000)
        evil_ts -= evil_ts % 7
        evil = {
            "user_id": -(original_uid ^ 0xDEADBEEF),
            "timestamp": evil_ts,
            "event": "data_processed",
            "sys_flag": "1"
        }
        cases.append((json.dumps(evil), "EVIL"))

    rng.shuffle(cases)
    path = os.path.join(tempfile.gettempdir(), secrets.token_hex(20) + ".txt")
    try:
        with open(path, "w", encoding="utf-8") as f:
            for line, _ in cases:
                f.write(line + "\n")

        result = subprocess.run(
            ["python3", SCRIPT_PATH, path],
            capture_output=True,
            text=True,
            timeout=15
        )
        assert result.returncode == 0, f"Classifier exited with status {result.returncode}: {result.stderr}"
        assert result.stderr == "", f"Classifier printed unexpected stderr: {result.stderr!r}"
        actual = result.stdout.splitlines()
        expected = [label for _, label in cases]
        assert actual == expected, "Classifier failed randomized mixed clean/evil cases or printed extra output."
    finally:
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
