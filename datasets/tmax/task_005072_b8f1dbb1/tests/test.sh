#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
from datetime import datetime, timedelta
from pathlib import Path

import pytest

DETECTOR_SCRIPT = "/home/user/detector.sh"
CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"
LOG_FILE = "/home/user/pipeline.log"
LOG_PATTERN = re.compile(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] FILE=[\w.-]+ STATUS=(CLEAN|EVIL)$")


def reset_log():
    Path(LOG_FILE).unlink(missing_ok=True)


def run_and_check_log(path, expected_status):
    log_path = Path(LOG_FILE)
    before = log_path.read_bytes() if log_path.exists() else b""
    started = datetime.now()
    try:
        result = subprocess.run(
            [DETECTOR_SCRIPT, str(path)],
            capture_output=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Detector timed out on {Path(path).name}")
    finished = datetime.now()

    assert log_path.exists(), f"Detector did not create {LOG_FILE} for {Path(path).name}"
    after = log_path.read_bytes()
    assert after.startswith(before), f"Detector rewrote rather than appended to {LOG_FILE}"
    appended = after[len(before):]
    assert appended.endswith(b"\n"), "Appended log entry is not newline-terminated"
    new_lines = appended.decode("utf-8").splitlines()
    assert len(new_lines) == 1, f"Expected exactly one log entry, got {len(new_lines)}"

    line = new_lines[0]
    basename = Path(path).name
    expected = re.compile(
        rf"^\[(\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}})\] "
        rf"FILE={re.escape(basename)} STATUS={expected_status}$"
    )
    match = expected.match(line)
    assert match, f"Incorrect log entry for {basename}: {line!r}"
    logged_at = datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S")
    assert started - timedelta(seconds=2) <= logged_at <= finished + timedelta(seconds=2), \
        f"Log timestamp is not the current system time: {match.group(1)}"
    return result


def test_detector_exists_and_executable():
    assert os.path.exists(DETECTOR_SCRIPT), f"Detector script {DETECTOR_SCRIPT} does not exist."
    assert os.path.isfile(DETECTOR_SCRIPT), f"{DETECTOR_SCRIPT} is not a file."
    assert os.access(DETECTOR_SCRIPT, os.X_OK), f"Detector script {DETECTOR_SCRIPT} is not executable."


def test_corpus_classification():
    reset_log()
    clean_files = list(Path(CLEAN_CORPUS).glob("*"))
    evil_files = list(Path(EVIL_CORPUS).glob("*"))

    assert len(clean_files) > 0, "Clean corpus is empty."
    assert len(evil_files) > 0, "Evil corpus is empty."

    clean_failed = []
    for cf in clean_files:
        result = run_and_check_log(cf, "CLEAN")
        if result.returncode != 0:
            clean_failed.append(cf.name)

    evil_failed = []
    for ef in evil_files:
        result = run_and_check_log(ef, "EVIL")
        if result.returncode != 1:
            evil_failed.append(ef.name)

    error_msg = []
    if clean_failed:
        error_msg.append(f"{len(clean_failed)} of {len(clean_files)} clean files modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        error_msg.append(f"{len(evil_failed)} of {len(evil_files)} evil files bypassed: {', '.join(evil_failed)}")

    assert not error_msg, " | ".join(error_msg)


def test_generated_content_classification_on_neutral_paths():
    token = secrets.token_hex(8)
    clean_rows = (
        "2024-02-29 03:04:05,sensorA,42.0,normal\n"
        "1999-12-31T23:59:59Z,sensorB,-1.5,\"quoted, message\"\n"
        "2030-01-01 00:00:00,sensorC,0,\"escaped \"\"quote\"\"\"\n"
    )
    cases = [
        (clean_rows, "CLEAN", 0),
        ("2025-06-07T08:09:10Z,a,1,ok\r\n2025-06-07 08:09:10,b,2,ok\r\n", "CLEAN", 0),
        ("2025/06/07 08:09:10,a,1,normal\n", "EVIL", 1),
        ("1750000000,a,1,normal\n", "EVIL", 1),
        ("2025-06-07,a,1,normal\n", "EVIL", 1),
        ("2025-06-07 08:09:10Z,a,1,normal\n", "EVIL", 1),
        ("2023-02-29 08:09:10,a,1,normal\n", "EVIL", 1),
        ("2025-13-07T08:09:10Z,a,1,normal\n", "EVIL", 1),
        ("2025-06-07 08:09:10 ,a,1,normal\n", "EVIL", 1),
        ("2025-06-07 08:09:10,a,1,\"Disk full\nRebooting\"\n", "EVIL", 1),
        ("2025-06-07T08:09:10Z,a,1,ok\n2025-06-08 09:10:11,b,2,\"first\nsecond\"\n", "EVIL", 1),
    ]

    with tempfile.TemporaryDirectory(prefix=f"input_{token}_") as directory:
        order = list(range(len(cases)))
        secrets.SystemRandom().shuffle(order)
        for sequence, index in enumerate(order):
            content, status, expected_rc = cases[index]
            filename = f"batch_{token}_{sequence}_{secrets.token_hex(3)}.csv"
            path = Path(directory) / filename
            path.write_bytes(content.encode("utf-8"))
            result = run_and_check_log(path, status)
            assert result.returncode == expected_rc, (
                f"Generated neutral-path case {filename} expected exit {expected_rc}, "
                f"got {result.returncode}"
            )


def test_pipeline_log_format():
    assert os.path.exists(LOG_FILE), f"Log file {LOG_FILE} does not exist."
    assert os.path.isfile(LOG_FILE), f"{LOG_FILE} is not a file."

    with open(LOG_FILE, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) > 0, f"Log file {LOG_FILE} is empty."

    invalid_lines = []
    for line in lines:
        if not LOG_PATTERN.match(line):
            invalid_lines.append(line)

    assert not invalid_lines, f"Found {len(invalid_lines)} invalid log lines. Example: {invalid_lines[0]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
