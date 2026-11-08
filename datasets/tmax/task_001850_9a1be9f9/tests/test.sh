#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
from datetime import datetime, timedelta

import pytest

DETECTOR_SCRIPT = "/home/user/detector.py"
CLEAN_CORPUS_DIR = "/app/corpora/clean/"
EVIL_CORPUS_DIR = "/app/corpora/evil/"
OVERRIDE_CODE = "ALFA-TANGO-7"


def invoke(filepath):
    return subprocess.run(
        ["python3", DETECTOR_SCRIPT, filepath],
        capture_output=True,
        timeout=10,
    )


def check_generated_log(lines, expected):
    fd, path = tempfile.mkstemp(prefix="log_" + secrets.token_hex(8) + "_", suffix=".txt")
    try:
        with os.fdopen(fd, "w") as handle:
            handle.write("\n".join(lines) + "\n")
        result = invoke(path)
        assert result.returncode == expected, (
            f"Generated log returned {result.returncode}, expected {expected}. "
            f"stderr={result.stderr.decode(errors='replace')!r}"
        )
    finally:
        os.unlink(path)


def line(ts, user, action, payload):
    return f'[{ts:%Y-%m-%d %H:%M:%S}] {user} {action} "{payload}"'


def test_detector_script_exists():
    assert os.path.exists(DETECTOR_SCRIPT), f"Detector script not found at {DETECTOR_SCRIPT}"
    assert os.path.isfile(DETECTOR_SCRIPT), f"{DETECTOR_SCRIPT} is not a file"


def test_clean_corpus_preserved():
    assert os.path.exists(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "No files found in clean corpus"

    failed_files = []
    for filepath in clean_files:
        result = invoke(filepath)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean logs were incorrectly rejected (exit code != 0). Offending files: {', '.join(failed_files)}")


def test_evil_corpus_rejected():
    assert os.path.exists(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "No files found in evil corpus"

    failed_files = []
    for filepath in evil_files:
        result = invoke(filepath)
        if result.returncode != 1:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil logs bypassed the detector (exit code != 1). Offending files: {', '.join(failed_files)}")


def test_generated_override_code_detection():
    base = datetime(2025, 2, 3, 8, 17, 21)
    user = "U" + secrets.token_hex(4)
    check_generated_log([
        line(base, user, "LOGIN", "ordinary startup"),
        line(base + timedelta(seconds=2), user, "ACTION", f"prefix {OVERRIDE_CODE} suffix"),
    ], 1)

    check_generated_log([
        line(base, user, "ACTION", "ALFA-TANGO-8"),
        line(base + timedelta(seconds=2), user, "LOGOUT", "ordinary shutdown"),
    ], 0)


def test_generated_burst_detection_and_boundaries():
    base = datetime(2024, 7, 9, 13, 24, 36)
    user = "B" + secrets.token_hex(4)

    check_generated_log([
        line(base, user, "ACTION", f"command-{i}-{secrets.token_hex(2)}")
        for i in range(5)
    ], 1)

    check_generated_log([
        line(base, user, "ACTION", f"allowed-{i}-{secrets.token_hex(2)}")
        for i in range(4)
    ], 0)

    other = "C" + secrets.token_hex(4)
    check_generated_log([
        line(base, user if i < 3 else other, "ACTION", f"split-{i}-{secrets.token_hex(2)}")
        for i in range(5)
    ], 0)


def test_generated_reboot_gap_detection_and_boundaries():
    base = datetime(2026, 1, 12, 4, 5, 6)
    user = "R" + secrets.token_hex(4)

    check_generated_log([
        line(base, user, "ACTION", "normal operation"),
        line(base + timedelta(seconds=11), user, "SYSTEM_REBOOT", "restarting"),
    ], 1)

    check_generated_log([
        line(base, user, "ACTION", "normal operation"),
        line(base + timedelta(seconds=10), user, "SYSTEM_REBOOT", "scheduled restart"),
    ], 0)

    check_generated_log([
        line(base, user, "ACTION", "normal operation"),
        line(base + timedelta(seconds=11), user, "ACTION", "still normal"),
        line(base + timedelta(seconds=12), user, "SYSTEM_REBOOT", "scheduled restart"),
    ], 0)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
