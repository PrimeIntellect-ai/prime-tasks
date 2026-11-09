#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import subprocess
import tempfile
import uuid
from decimal import Decimal

import pytest

SCRIPT_PATH = "/home/user/detect.py"
CLEAN_CORPUS_DIR = "/tmp/clean_corpus"
EVIL_CORPUS_DIR = "/tmp/evil_corpus"
THRESHOLD_IMAGE = "/app/threshold.png"


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Expected script at {SCRIPT_PATH} does not exist."


def test_adversarial_corpus():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus dir {CLEAN_CORPUS_DIR} missing."
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus dir {EVIL_CORPUS_DIR} missing."

    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.log"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.log"))

    assert len(clean_files) > 0, "No clean log files found."
    assert len(evil_files) > 0, "No evil log files found."

    clean_failures = []
    for f in clean_files:
        result = subprocess.run(["python3", SCRIPT_PATH, f], capture_output=True)
        if result.returncode != 0:
            clean_failures.append((os.path.basename(f), result.returncode, result.stderr.decode("utf-8")))

    evil_failures = []
    for f in evil_files:
        result = subprocess.run(["python3", SCRIPT_PATH, f], capture_output=True)
        if result.returncode != 1:
            evil_failures.append((os.path.basename(f), result.returncode, result.stderr.decode("utf-8")))

    error_msgs = []
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed:")
        for name, code, err in evil_failures:
            error_msgs.append(f"  - {name} (exit code {code})")

    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected:")
        for name, code, err in clean_failures:
            error_msgs.append(f"  - {name} (exit code {code})")

    if error_msgs:
        pytest.fail("\n".join(error_msgs))


def read_threshold():
    assert os.path.isfile(THRESHOLD_IMAGE), f"Threshold image {THRESHOLD_IMAGE} missing."
    result = subprocess.run(
        ["tesseract", THRESHOLD_IMAGE, "stdout", "-l", "eng"],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, result.stderr
    match = re.search(r"MAX_ALLOWED_LOSS\s*=\s*([0-9]+(?:\.[0-9]+)?)", result.stdout)
    assert match, f"Could not extract MAX_ALLOWED_LOSS from image OCR: {result.stdout!r}"
    return Decimal(match.group(1))


def test_generated_unlabelled_corpus():
    threshold = read_threshold()
    assert threshold > 0

    rng = random.SystemRandom()
    corpus_dir = tempfile.mkdtemp(prefix=f"tx-{uuid.uuid4().hex}-", dir="/tmp")
    epsilon = threshold / Decimal(4)
    cases = [
        (Decimal(0), 0),
        (threshold / Decimal(2), 0),
        (threshold, 0),
        (threshold + epsilon, 1),
        (threshold * Decimal(2), 1),
        (threshold * Decimal(5), 1),
    ]

    failures = []
    for loss, expected_code in cases:
        tx_id = str(uuid.uuid4())
        initial = Decimal(rng.randrange(20, 900)) + Decimal(rng.randrange(100000, 999999)) / Decimal(1000000)
        direction = Decimal(1) if rng.randrange(2) else Decimal(-1)
        final_amount = initial + direction * loss

        entries = [
            {"service": "gateway", "tx_id": tx_id, "amount": format(initial, "f")},
            {"service": "processor", "tx_id": tx_id, "status": "processing", "sequence": rng.randrange(1000)},
            {"service": "settlement", "tx_id": tx_id, "final_amount": float(final_amount)},
        ]
        rng.shuffle(entries)

        path = os.path.join(corpus_dir, f"{uuid.uuid4().hex}.log")
        with open(path, "w", encoding="utf-8") as handle:
            for entry in entries:
                handle.write(json.dumps(entry, separators=(",", ":")) + "\n")

        result = subprocess.run(
            ["python3", SCRIPT_PATH, path],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode != expected_code:
            failures.append(
                f"generated case {os.path.basename(path)} returned {result.returncode}, "
                f"expected {expected_code}; stderr={result.stderr!r}"
            )

    assert not failures, "\n".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
