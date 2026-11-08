#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import secrets
import string
import subprocess
import tempfile
from pathlib import Path
import pytest

def test_detector_script_exists():
    detector_path = Path("/home/user/detector.py")
    assert detector_path.exists() and detector_path.is_file(), f"Detector script not found at {detector_path}"

def test_adversarial_corpus():
    detector_path = "/home/user/detector.py"
    evil_dir = Path("/app/corpus/evil")
    clean_dir = Path("/app/corpus/clean")

    assert evil_dir.exists() and evil_dir.is_dir(), f"Evil corpus directory missing: {evil_dir}"
    assert clean_dir.exists() and clean_dir.is_dir(), f"Clean corpus directory missing: {clean_dir}"

    evil_files = list(evil_dir.glob("*"))
    clean_files = list(clean_dir.glob("*"))

    assert len(evil_files) > 0, "No files found in evil corpus."
    assert len(clean_files) > 0, "No files found in clean corpus."

    evil_bypassed = []
    clean_rejected = []

    # Test evil corpus
    for evil_file in evil_files:
        result = subprocess.run(
            ["python3", detector_path, str(evil_file)],
            capture_output=True,
            text=True
        )
        if result.returncode != 1 or "REJECT" not in result.stdout:
            evil_bypassed.append(evil_file.name)

    # Test clean corpus
    for clean_file in clean_files:
        result = subprocess.run(
            ["python3", detector_path, str(clean_file)],
            capture_output=True,
            text=True
        )
        if result.returncode != 0 or "ACCEPT" not in result.stdout:
            clean_rejected.append(clean_file.name)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_rejected:
        errors.append(f"{len(clean_rejected)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_rejected)}")

    if errors:
        pytest.fail(" | ".join(errors))

def test_generated_content_independent_of_path():
    detector_path = "/home/user/detector.py"
    rng = random.SystemRandom()
    hexsets = [string.digits, "abcdef", "ABCDEF", string.hexdigits[:22]]

    cases = []
    for i in range(16):
        alphabet = hexsets[i % len(hexsets)]
        token = "".join(secrets.choice(alphabet) for _ in range(8))
        left = secrets.token_urlsafe(9)
        right = secrets.token_urlsafe(9)
        cases.append((f"{left}\nmessage=CRITICAL_VULN_{token}!\n{right}\n", 1, "REJECT"))

    for _ in range(6):
        token = "".join(secrets.choice(string.hexdigits[:22]) for _ in range(7))
        cases.append((f"short marker CRITICAL_VULN_{token}!", 0, "ACCEPT"))

    for _ in range(8):
        chars = [secrets.choice(string.hexdigits[:22]) for _ in range(8)]
        chars[rng.randrange(8)] = secrets.choice("ghijklmnopqrstuvwxyzGHIJKLMNOPQRSTUVWXYZ")
        cases.append((f"non-hex marker CRITICAL_VULN_{''.join(chars)}!", 0, "ACCEPT"))

    cases.extend([
        ("CRITICAL_VULN_ without a hexadecimal value", 0, "ACCEPT"),
        ("CRITICAL-VULN-deadbeef", 0, "ACCEPT"),
        ("ordinary clean processing log", 0, "ACCEPT"),
    ])
    rng.shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="detector-check-") as temp_dir:
        # Every case uses the same neutral path, so classification must depend on content.
        sample = Path(temp_dir) / "sample.dat"
        for index, (content, expected_code, expected_output) in enumerate(cases):
            sample.write_text(content, encoding="utf-8")
            try:
                result = subprocess.run(
                    ["python3", detector_path, str(sample)],
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
            except subprocess.TimeoutExpired:
                failures.append(f"case {index}: detector timed out")
                continue

            if result.returncode != expected_code or result.stdout.strip() != expected_output:
                failures.append(
                    f"case {index}: expected code/output {expected_code}/{expected_output}, "
                    f"got {result.returncode}/{result.stdout.strip()!r}"
                )

    assert not failures, " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
