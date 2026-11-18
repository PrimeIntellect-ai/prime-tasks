#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import glob
import json
import random
import secrets
import subprocess
from datetime import datetime, timezone, timedelta
import pytest

CLEAN_DIR = "/home/user/data/clean"
EVIL_DIR = "/home/user/data/evil"
VALIDATE_SCRIPT = "/home/user/validate.py"
CALIBRATION_EPOCH = datetime(2024, 1, 1, tzinfo=timezone.utc)
MAX_RPM = 8450.5


def run_validator(path):
    return subprocess.run(
        ["python3", VALIDATE_SCRIPT, str(path)],
        capture_output=True,
        timeout=10,
    )


def test_validate_script_exists():
    assert os.path.isfile(VALIDATE_SCRIPT), f"Validation script not found at {VALIDATE_SCRIPT}"


def test_data_directories_exist():
    assert os.path.isdir(CLEAN_DIR), f"Clean data directory not found at {CLEAN_DIR}. Did you download and extract the archive?"
    assert os.path.isdir(EVIL_DIR), f"Evil data directory not found at {EVIL_DIR}. Did you download and extract the archive?"


def test_adversarial_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*"))
    evil_files = glob.glob(os.path.join(EVIL_DIR, "*"))

    assert len(clean_files) > 0, f"No clean files found in {CLEAN_DIR}."
    assert len(evil_files) > 0, f"No evil files found in {EVIL_DIR}."

    clean_failed = []
    for cf in clean_files:
        if not os.path.isfile(cf):
            continue
        res = run_validator(cf)
        if res.returncode != 0:
            clean_failed.append(os.path.basename(cf))

    evil_bypassed = []
    for ef in evil_files:
        if not os.path.isfile(ef):
            continue
        res = run_validator(ef)
        if res.returncode == 0:
            evil_bypassed.append(os.path.basename(ef))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failed)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed (accepted): {', '.join(evil_bypassed)}")

    assert not errors, " | ".join(errors)


def expected_valid(document):
    if not isinstance(document, dict):
        return False
    if "timestamp" not in document or "rpm" not in document:
        return False
    timestamp = document["timestamp"]
    rpm = document["rpm"]
    if not isinstance(timestamp, str):
        return False
    if isinstance(rpm, bool) or not isinstance(rpm, (int, float)):
        return False
    if not (float("-inf") < float(rpm) < float("inf")):
        return False
    try:
        normalized = timestamp[:-1] + "+00:00" if timestamp.endswith("Z") else timestamp
        parsed = datetime.fromisoformat(normalized)
        if parsed.tzinfo is None or parsed.utcoffset() is None:
            return False
        utc_time = parsed.astimezone(timezone.utc)
    except (TypeError, ValueError, OverflowError):
        return False
    return utc_time >= CALIBRATION_EPOCH and 0.0 <= rpm <= MAX_RPM


def test_generated_behavior_in_unlabelled_directory(tmp_path):
    # Valid and invalid payloads deliberately share one unpredictable directory,
    # so classification cannot be inferred from directory or file names.
    cases = [
        {"timestamp": "2024-01-01T00:00:00Z", "rpm": 0.0},
        {"timestamp": "2024-01-01T05:00:00+05:00", "rpm": MAX_RPM},
        {"timestamp": "2023-12-31T23:59:59.999999Z", "rpm": 1},
        {"timestamp": "2024-01-01T01:00:00+02:00", "rpm": 1000},
        {"timestamp": "2026-06-01T12:30:00-07:00", "rpm": MAX_RPM + 0.0001},
        {"timestamp": "2026-06-01T12:30:00-07:00", "rpm": -0.0001},
        {"timestamp": "not-a-timestamp", "rpm": 100},
        {"timestamp": "2024-01-01T00:00:00", "rpm": 100},
        {"timestamp": 1704067200, "rpm": 100},
        {"timestamp": "2025-01-01T00:00:00Z", "rpm": "100"},
        {"timestamp": "2025-01-01T00:00:00Z", "rpm": True},
        {"timestamp": "2025-01-01T00:00:00Z"},
        {"rpm": 100},
        ["2025-01-01T00:00:00Z", 100],
    ]

    # Build additional cases from random instants, offsets, and RPM values. The
    # expected result is independently calculated from the actual payload.
    for _ in range(30):
        seconds = random.randint(-172800, 90000000)
        instant = CALIBRATION_EPOCH + timedelta(seconds=seconds)
        offset_minutes = random.choice([-720, -480, -300, 0, 60, 120, 330, 345, 600, 840])
        local_time = instant.astimezone(timezone(timedelta(minutes=offset_minutes)))
        timestamp = local_time.isoformat(timespec="seconds")
        if offset_minutes == 0 and random.choice([True, False]):
            timestamp = timestamp.replace("+00:00", "Z")
        rpm = random.choice([
            round(random.uniform(0.0, MAX_RPM), 5),
            round(random.uniform(-500.0, -0.001), 5),
            round(random.uniform(MAX_RPM + 0.001, MAX_RPM + 500.0), 5),
        ])
        cases.append({"timestamp": timestamp, "rpm": rpm, "tag": secrets.token_hex(4)})

    random.shuffle(cases)
    outcomes = []
    for document in cases:
        path = tmp_path / (secrets.token_hex(12) + ".json")
        padding = " " * random.randint(0, 17)
        path.write_text(padding + json.dumps(document) + "\n" + padding, encoding="utf-8")
        expected_code = 0 if expected_valid(document) else 1
        result = run_validator(path)
        outcomes.append(expected_code)
        assert result.returncode == expected_code, (
            f"Wrong exit status for generated payload {document!r}: "
            f"expected {expected_code}, got {result.returncode}; stderr={result.stderr!r}"
        )

    assert 0 in outcomes and 1 in outcomes


def test_malformed_missing_and_non_file_inputs(tmp_path):
    malformed_contents = [
        "",
        "{",
        "this is not json",
        '{"timestamp":"2025-01-01T00:00:00Z","rpm":NaN}',
        '{"timestamp":"2025-01-01T00:00:00Z","rpm":Infinity}',
    ]
    for content in malformed_contents:
        path = tmp_path / (secrets.token_hex(12) + ".json")
        path.write_text(content, encoding="utf-8")
        result = run_validator(path)
        assert result.returncode == 1, f"Malformed JSON was not rejected: {content!r}"

    missing = tmp_path / (secrets.token_hex(12) + ".json")
    assert run_validator(missing).returncode == 1
    assert run_validator(tmp_path).returncode == 1

    no_argument = subprocess.run(["python3", VALIDATE_SCRIPT], capture_output=True, timeout=10)
    assert no_argument.returncode == 1
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
