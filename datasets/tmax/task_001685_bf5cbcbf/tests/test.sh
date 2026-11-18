#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import re
import secrets
import subprocess
import tempfile
from decimal import Decimal
from pathlib import Path

SCRIPT_PATH = "/home/user/filter.sh"


def test_filter_script_exists_and_executable():
    script_path = SCRIPT_PATH
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable. Did you run chmod +x?"


def test_adversarial_corpus():
    script_path = SCRIPT_PATH
    clean_dir = Path("/app/clean")
    evil_dir = Path("/app/evil")

    assert clean_dir.is_dir(), f"{clean_dir} directory is missing."
    assert evil_dir.is_dir(), f"{evil_dir} directory is missing."

    clean_files = list(clean_dir.iterdir())
    evil_files = list(evil_dir.iterdir())

    assert len(clean_files) > 0, "No clean files found."
    assert len(evil_files) > 0, "No evil files found."

    clean_failed = []
    for cf in clean_files:
        result = subprocess.run([script_path, str(cf)], capture_output=True)
        if result.returncode != 0:
            clean_failed.append(cf.name)

    evil_bypassed = []
    for ef in evil_files:
        result = subprocess.run([script_path, str(ef)], capture_output=True)
        if result.returncode != 1:
            evil_bypassed.append(ef.name)

    error_messages = []
    if clean_failed:
        error_messages.append(f"{len(clean_failed)} of {len(clean_files)} clean files failed (expected exit 0, got something else). Offending files: {', '.join(clean_failed[:10])}{'...' if len(clean_failed) > 10 else ''}")

    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil files bypassed (expected exit 1, got something else). Offending files: {', '.join(evil_bypassed[:10])}{'...' if len(evil_bypassed) > 10 else ''}")

    assert not error_messages, " | ".join(error_messages)


def threshold_from_spec():
    result = subprocess.run(
        ["tesseract", "/app/specs.png", "stdout", "--psm", "7"],
        capture_output=True,
        text=True,
        check=True,
    )
    numbers = re.findall(r"\d+\.\d+", result.stdout)
    assert numbers, f"Could not extract a decimal threshold from specs.png; OCR output was {result.stdout!r}"
    return Decimal(numbers[-1])


def test_generated_logs_at_unpredictable_paths():
    threshold = threshold_from_spec()
    exact = format(threshold, "f")
    below_cent = format(threshold - Decimal("0.01"), "f")
    below_milli = format(threshold - Decimal("0.001"), "f")
    above_cent = format(threshold + Decimal("0.01"), "f")
    above_milli = format(threshold + Decimal("0.001"), "f")

    # Names are opaque and generated only after the agent has finished, so a
    # classifier must inspect the bytes rather than recognize corpus paths.
    cases = [
        ((exact + "\n").encode("utf-8"), 0),
        (("150.5\n" + below_cent + "\n" + exact + "\n").encode("utf-8"), 0),
        (("-42.75\n0\n" + below_milli + "\n").encode("utf-8"), 0),
        ((above_cent + "\n").encode("utf-8"), 1),
        (("1.25\n" + above_milli + "\n2.50\n").encode("utf-8"), 1),
        (("999999999999999999999999.99\n").encode("utf-8"), 1),
        (b"12.5\n\xff\xfe\n", 1),
        (exact.encode("utf-8") + b"\n\x80\n", 1),
    ]
    random.SystemRandom().shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="sensor-check-") as temp_dir:
        for payload, expected in cases:
            path = Path(temp_dir) / secrets.token_hex(16)
            path.write_bytes(payload)
            result = subprocess.run([SCRIPT_PATH, str(path)], capture_output=True)
            if result.returncode != expected:
                failures.append(
                    f"{path.name}: expected {expected}, got {result.returncode}"
                )

    assert not failures, "Generated-log classification failures: " + "; ".join(failures)


def test_no_forbidden_languages():
    script_path = SCRIPT_PATH
    with open(script_path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    forbidden = ["python", "perl", "ruby", "node"]
    for lang in forbidden:
        assert lang not in content.lower(), f"Script appears to use forbidden language: {lang}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
