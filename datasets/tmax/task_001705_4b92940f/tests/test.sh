#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import shutil
import subprocess
import tempfile

import pytest

SANITIZER_SCRIPT = "/home/user/sanitizer.py"
CLEAN_DIR = "/app/data/clean"
EVIL_DIR = "/app/data/evil"


def test_sanitizer_exists():
    assert os.path.isfile(SANITIZER_SCRIPT), f"Sanitizer script not found at {SANITIZER_SCRIPT}"
    assert os.access(SANITIZER_SCRIPT, os.R_OK), "Sanitizer script is not readable."


def test_sanitizer_clean_corpus():
    assert os.path.isdir(CLEAN_DIR), f"Clean directory missing: {CLEAN_DIR}"

    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if f.endswith(".json")]
    assert len(clean_files) > 0, "No clean JSON files found."

    modified_clean = []

    for file_path in clean_files:
        result = subprocess.run(
            ["python3", SANITIZER_SCRIPT, file_path],
            capture_output=True,
            text=True
        )

        output = result.stdout.strip()
        if result.returncode != 0 or output != "SAFE":
            modified_clean.append(os.path.basename(file_path))

    if modified_clean:
        pytest.fail(f"{len(modified_clean)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(modified_clean)}")


def test_sanitizer_evil_corpus():
    assert os.path.isdir(EVIL_DIR), f"Evil directory missing: {EVIL_DIR}"

    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if f.endswith(".json")]
    assert len(evil_files) > 0, "No evil JSON files found."

    bypassed_evil = []

    for file_path in evil_files:
        result = subprocess.run(
            ["python3", SANITIZER_SCRIPT, file_path],
            capture_output=True,
            text=True
        )

        output = result.stdout.strip()
        if result.returncode != 1 or output != "UNSAFE":
            bypassed_evil.append(os.path.basename(file_path))

    if bypassed_evil:
        pytest.fail(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed/accepted. Offending files: {', '.join(bypassed_evil)}")


def test_sanitizer_generated_holdout():
    holdout_dir = tempfile.mkdtemp(prefix="payloads_" + secrets.token_hex(8) + "_")
    cases = []

    def add_case(alpha, beta, gamma):
        payload = {"alpha": alpha, "beta": beta, "gamma": gamma}
        unsafe = abs(math.exp(alpha) - beta) < 1e-5 or gamma < 0.0
        path = os.path.join(holdout_dir, secrets.token_hex(16) + ".json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(payload, f)
        cases.append((path, unsafe))

    try:
        # Safe values, including gamma exactly zero and values just safely outside
        # the exponential-distance threshold.
        for _ in range(40):
            alpha = secrets.SystemRandom().uniform(-6.0, 6.0)
            delta = secrets.choice((-0.5, -0.01, -0.00003, 0.00003, 0.01, 0.5))
            gamma = secrets.choice((0.0, 0.125, 2.5, 100.0))
            add_case(alpha, math.exp(alpha) + delta, gamma)

        # Inputs unsafe solely because beta is within the numerical threshold.
        for _ in range(40):
            alpha = secrets.SystemRandom().uniform(-6.0, 6.0)
            delta = secrets.choice((0.0, -0.000005, -0.0000001, 0.0000001, 0.000005))
            gamma = secrets.choice((0.0, 0.25, 10.0))
            add_case(alpha, math.exp(alpha) + delta, gamma)

        # Inputs unsafe solely because gamma is negative.
        for _ in range(40):
            alpha = secrets.SystemRandom().uniform(-6.0, 6.0)
            delta = secrets.choice((-1.0, -0.01, 0.01, 1.0))
            gamma = -secrets.SystemRandom().uniform(0.000001, 100.0)
            add_case(alpha, math.exp(alpha) + delta, gamma)

        # Inputs satisfying both unsafe conditions.
        for _ in range(20):
            alpha = secrets.SystemRandom().uniform(-6.0, 6.0)
            delta = secrets.choice((0.0, -0.000001, 0.000001))
            gamma = -secrets.SystemRandom().uniform(0.000001, 10.0)
            add_case(alpha, math.exp(alpha) + delta, gamma)

        secrets.SystemRandom().shuffle(cases)
        failures = []
        for path, unsafe in cases:
            try:
                result = subprocess.run(
                    ["python3", SANITIZER_SCRIPT, path],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
            except subprocess.TimeoutExpired:
                failures.append(f"{os.path.basename(path)}: timed out")
                continue

            expected_code = 1 if unsafe else 0
            expected_output = "UNSAFE\n" if unsafe else "SAFE\n"
            if result.returncode != expected_code or result.stdout != expected_output:
                failures.append(
                    f"{os.path.basename(path)}: expected code {expected_code} and "
                    f"stdout {expected_output!r}, got code {result.returncode} and "
                    f"stdout {result.stdout!r}"
                )

        if failures:
            pytest.fail(f"{len(failures)} generated holdout cases failed: " + "; ".join(failures[:10]))
    finally:
        shutil.rmtree(holdout_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
