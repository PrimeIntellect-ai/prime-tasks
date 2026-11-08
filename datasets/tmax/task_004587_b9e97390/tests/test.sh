#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess
import uuid
from decimal import Decimal, ROUND_HALF_EVEN

import pytest

SCRIPT_PATH = "/home/user/sanitizer.py"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"


def run_sanitizer(path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, str(path)],
        capture_output=True,
        timeout=5,
    )


def expected_safe(value):
    rounded = Decimal(str(value)).quantize(Decimal("0.0001"), rounding=ROUND_HALF_EVEN)
    return rounded % Decimal("0.25") == 0


def test_sanitizer_exists():
    """Ensure the user created the sanitizer script."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"


def test_adversarial_corpus():
    """Test the sanitizer script against the clean and evil corpora."""
    assert os.path.exists(CLEAN_CORPUS_DIR), "Clean corpus directory missing."
    assert os.path.exists(EVIL_CORPUS_DIR), "Evil corpus directory missing."

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]

    assert clean_files, "No clean corpus files found."
    assert evil_files, "No evil corpus files found."

    clean_failures = []
    for cf in clean_files:
        result = run_sanitizer(cf)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(cf))

    evil_failures = []
    for ef in evil_files:
        result = run_sanitizer(ef)
        if result.returncode != 1:
            evil_failures.append(os.path.basename(ef))

    error_messages = []
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean files modified/rejected: {', '.join(clean_failures)}")
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil files bypassed: {', '.join(evil_failures)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def test_generated_payloads(tmp_path):
    """Exercise freshly generated clean and unsafe values at indistinguishable paths."""
    rng = secrets.SystemRandom()
    cases = []

    # Multiples of 0.25 with ordinary floating-point noise that disappears
    # when rounded to four decimal places.
    for _ in range(48):
        quarter = rng.randint(-32, 32) / 4.0
        value = quarter + rng.uniform(-0.000004, 0.000004)
        assert expected_safe(value)
        cases.append((value, 0))

    # Exact four-decimal values which are not multiples of 0.25.
    while len(cases) < 96:
        units = rng.randint(-80000, 80000)
        value = units / 10000.0
        if expected_safe(value):
            continue
        cases.append((value, 1))

    random.SystemRandom().shuffle(cases)
    failures = []
    for value, expected_code in cases:
        payload_path = tmp_path / (uuid.uuid4().hex + ".json")
        payload_path.write_text(json.dumps({"tz_offset_hours": value}), encoding="utf-8")
        result = run_sanitizer(payload_path)
        if result.returncode != expected_code:
            failures.append(
                f"value {value!r}: expected exit {expected_code}, got {result.returncode}"
            )

    assert not failures, "Generated payload failures: " + " | ".join(failures[:10])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
