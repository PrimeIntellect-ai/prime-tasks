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

import pytest

DETECTOR_PATH = "/home/user/detector"
SOURCE_PATH = "/home/user/detector.cpp"
EVIL_CORPUS_DIR = "/opt/corpus/evil"
CLEAN_CORPUS_DIR = "/opt/corpus/clean"


def test_detector_exists_and_executable():
    assert os.path.isfile(DETECTOR_PATH), f"Executable not found at {DETECTOR_PATH}"
    assert os.access(DETECTOR_PATH, os.X_OK), f"File at {DETECTOR_PATH} is not executable"


def test_detector_is_compiled_artifact():
    assert os.path.isfile(SOURCE_PATH), f"Source not found at {SOURCE_PATH}"
    with open(DETECTOR_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File at {DETECTOR_PATH} is not an ELF executable"


def test_adversarial_corpus():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    assert len(evil_files) > 0, "No files found in evil corpus."
    assert len(clean_files) > 0, "No files found in clean corpus."

    evil_bypassed = []
    for evil_file in evil_files:
        result = subprocess.run([DETECTOR_PATH, evil_file], capture_output=True)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(evil_file))

    clean_rejected = []
    for clean_file in clean_files:
        result = subprocess.run([DETECTOR_PATH, clean_file], capture_output=True)
        if result.returncode != 0:
            clean_rejected.append(os.path.basename(clean_file))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed[:5])}{'...' if len(evil_bypassed) > 5 else ''}")
    if clean_rejected:
        error_messages.append(f"{len(clean_rejected)} of {len(clean_files)} clean rejected: {', '.join(clean_rejected[:5])}{'...' if len(clean_rejected) > 5 else ''}")

    assert not evil_bypassed and not clean_rejected, " | ".join(error_messages)


SECRET_PATTERNS = (
    re.compile(r"password=[A-Za-z0-9]{16}"),
    re.compile(r"AKIA[0-9A-Z]{16}"),
)
TIMESTAMP = re.compile(r"^\[(\d{4}-\d{2}-\d{2}) (\d{2}):\d{2}:\d{2}\]")
ALNUM = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
UPPER_DIGITS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
RNG = secrets.SystemRandom()


def token(alphabet, length):
    return "".join(RNG.choice(alphabet) for _ in range(length))


def expected_exit(lines):
    hourly = {}
    for line in lines:
        match = TIMESTAMP.match(line)
        assert match, f"Verifier generated malformed line: {line!r}"
        hour = (match.group(1), match.group(2))
        hourly[hour] = hourly.get(hour, 0) + 1
        if hourly[hour] > 50:
            return 1
        if any(pattern.search(line) for pattern in SECRET_PATTERNS):
            return 1
    return 0


def normal_line(ts, value=None):
    if value is None:
        value = "VAL_" + token(ALNUM, 10)
    return f"[{ts.strftime('%Y-%m-%d %H:%M:%S')}] SERVICE CONFIG={value}"


def make_case(kind):
    base = datetime(RNG.randint(2020, 2028), RNG.randint(1, 11), RNG.randint(1, 20), RNG.randint(0, 18), 0, 0)
    lines = []

    if kind == "boundary50":
        for i in range(50):
            lines.append(normal_line(base + timedelta(minutes=i, seconds=RNG.randint(0, 59))))
    else:
        for hour_offset in range(RNG.randint(1, 4)):
            count = RNG.randint(2, 35)
            hour = base + timedelta(hours=hour_offset)
            for _ in range(count):
                lines.append(normal_line(hour + timedelta(minutes=RNG.randint(0, 59), seconds=RNG.randint(0, 59))))

    if kind == "anomaly":
        hour = base + timedelta(hours=RNG.randint(8, 20))
        for _ in range(RNG.randint(51, 58)):
            lines.append(normal_line(hour + timedelta(minutes=RNG.randint(0, 59), seconds=RNG.randint(0, 59))))
    elif kind == "password":
        ts = base + timedelta(hours=RNG.randint(5, 10), minutes=RNG.randint(0, 59))
        lines.append(normal_line(ts, "password=" + token(ALNUM, 16)))
    elif kind == "access_key":
        ts = base + timedelta(hours=RNG.randint(5, 10), minutes=RNG.randint(0, 59))
        lines.append(normal_line(ts, "AKIA" + token(UPPER_DIGITS, 16)))
    elif kind == "both":
        hour = base + timedelta(hours=RNG.randint(8, 20))
        for _ in range(51):
            lines.append(normal_line(hour + timedelta(minutes=RNG.randint(0, 59), seconds=RNG.randint(0, 59))))
        lines.append(normal_line(base + timedelta(hours=22), "password=" + token(ALNUM, 16)))
    elif kind == "near_miss":
        ts = base + timedelta(hours=6)
        lines.extend([
            normal_line(ts, "password=" + token(ALNUM, 15)),
            normal_line(ts + timedelta(minutes=1), "Password=" + token(ALNUM, 16)),
            normal_line(ts + timedelta(minutes=2), "AKIA" + token(UPPER_DIGITS, 15)),
            normal_line(ts + timedelta(minutes=3), "AKIa" + token(UPPER_DIGITS, 16)),
        ])

    lines.sort()
    return lines


def test_runtime_generated_corpus():
    kinds = (["boundary50"] * 4 + ["near_miss"] * 6 + ["clean"] * 8 +
             ["anomaly"] * 8 + ["password"] * 8 + ["access_key"] * 8 + ["both"] * 4)
    RNG.shuffle(kinds)

    failures = []
    with tempfile.TemporaryDirectory(prefix="detector-inputs-") as case_dir:
        cases = []
        for kind in kinds:
            lines = make_case(kind)
            path = os.path.join(case_dir, token(ALNUM, 24) + ".dat")
            with open(path, "w", encoding="utf-8") as f:
                f.write("\n".join(lines) + "\n")
            cases.append((path, expected_exit(lines)))

        RNG.shuffle(cases)
        for path, expected in cases:
            try:
                result = subprocess.run([DETECTOR_PATH, path], capture_output=True, timeout=5)
            except subprocess.TimeoutExpired:
                failures.append(f"{os.path.basename(path)} timed out")
                continue
            if result.returncode != expected:
                failures.append(f"{os.path.basename(path)} returned {result.returncode}, expected {expected}")

    assert not failures, "Generated corpus failures: " + "; ".join(failures[:10])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
