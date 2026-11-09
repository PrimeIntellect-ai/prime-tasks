#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import stat
import string
import subprocess
import tempfile

import pytest


def test_corrupted_string_extracted():
    filepath = "/home/user/corrupted_string.txt"
    assert os.path.isfile(filepath), f"File {filepath} is missing."

    with open(filepath, "r") as f:
        content = f.read().strip()

    expected = "CRITICAL_CORRUPT: x9F2kL0m"
    assert content == expected, f"Expected corrupted string to be '{expected}', but got '{content}'."


def test_final_counts_json():
    filepath = "/home/user/final_counts.json"
    assert os.path.isfile(filepath), f"File {filepath} is missing. Did you run the Go program?"

    with open(filepath, "r") as f:
        try:
            counts = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {filepath} does not contain valid JSON.")

    expected_counts = {
        "ERROR": 2,
        "FATAL": 1,
        "INFO": 6,
        "WARN": 3
    }
    assert counts == expected_counts, f"Expected counts {expected_counts}, but got {counts}."


def test_go_script_fixed():
    filepath = "/home/user/log_processor.go"
    assert os.path.isfile(filepath), f"File {filepath} is missing."
    assert stat.S_ISREG(os.stat(filepath).st_mode), f"File {filepath} is not a regular file."

    with open(filepath, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "len(lines)-1" not in content, "The off-by-one error `len(lines)-1` is still present in the Go script."
    has_mutex = "Mutex" in content
    has_sync_map = "sync.Map" in content
    has_channels = "chan " in content
    assert has_mutex or has_sync_map or has_channels, "No synchronization mechanism (Mutex, sync.Map, channels) found in the Go script to fix the race condition."


def _write_corpus(log_dir, rng, file_count, min_lines, max_lines):
    levels = ["INFO", "WARN", "ERROR", "FATAL"]
    expected = {level: 0 for level in levels}

    for file_index in range(file_count):
        suffix = ''.join(rng.choice(string.ascii_letters + string.digits) for _ in range(12))
        path = os.path.join(log_dir, f"batch_{file_index}_{suffix}.log")
        line_count = rng.randint(min_lines, max_lines)
        lines = []
        offset = rng.randrange(len(levels))
        for line_index in range(line_count):
            level = levels[(line_index + file_index + offset) % len(levels)]
            expected[level] += 1
            token = ''.join(rng.choice(string.ascii_letters + string.digits) for _ in range(18))
            lines.append(f"2026-09-{(file_index % 28) + 1:02d} {level} event-{token}")

        # Some files deliberately have no terminal newline, including their last valid line.
        data = "\n".join(lines)
        if file_index % 3 == 0:
            data += "\n"
        with open(path, "w") as f:
            f.write(data)

    return expected


def _run_and_check(binary, expected):
    output = "/home/user/final_counts.json"
    if os.path.exists(output):
        os.remove(output)

    env = os.environ.copy()
    env["GORACE"] = "halt_on_error=1 exitcode=97"
    result = subprocess.run(
        [binary],
        cwd="/tmp",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=45,
    )
    assert result.returncode == 0, (
        f"Compiled program failed (exit {result.returncode}).\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(output), "The compiled Go program did not create final_counts.json."

    with open(output, "rb") as f:
        raw = f.read()
    try:
        actual = json.loads(raw)
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        pytest.fail(f"The compiled program produced invalid JSON: {exc}")
    assert actual == expected, f"Expected dynamic counts {expected}, but got {actual}."
    return raw


def test_compiled_program_on_dynamic_inputs_repeatedly():
    source = "/home/user/log_processor.go"
    binary = "/tmp/log_processor_verified"
    build = subprocess.run(
        ["go", "build", "-race", "-o", binary, source],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=90,
    )
    assert build.returncode == 0, f"Go program does not compile with the race detector:\n{build.stderr}"

    log_dir = "/home/user/logs"
    backup_root = tempfile.mkdtemp(prefix="log-verifier-backup-")
    backup_logs = os.path.join(backup_root, "logs")
    final_path = "/home/user/final_counts.json"
    original_final = None
    if os.path.isfile(final_path):
        with open(final_path, "rb") as f:
            original_final = f.read()

    shutil.move(log_dir, backup_logs)
    os.mkdir(log_dir)
    try:
        rng = random.SystemRandom()

        # A small boundary-focused corpus tests one-line files and missing final newlines.
        expected = _write_corpus(log_dir, rng, 19, 1, 7)
        first = _run_and_check(binary, expected)
        assert _run_and_check(binary, expected) == first, "Repeated runs produced different JSON output."

        # Replace it with a large, highly concurrent corpus and run it repeatedly.
        shutil.rmtree(log_dir)
        os.mkdir(log_dir)
        expected = _write_corpus(log_dir, rng, 96, 220, 360)
        outputs = [_run_and_check(binary, expected) for _ in range(4)]
        assert all(raw == outputs[0] for raw in outputs), "Repeated runs produced inconsistent final_counts.json bytes."
    finally:
        if os.path.exists(log_dir):
            shutil.rmtree(log_dir)
        shutil.move(backup_logs, log_dir)
        shutil.rmtree(backup_root, ignore_errors=True)
        if original_final is not None:
            with open(final_path, "wb") as f:
                f.write(original_final)
        elif os.path.exists(final_path):
            os.remove(final_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
