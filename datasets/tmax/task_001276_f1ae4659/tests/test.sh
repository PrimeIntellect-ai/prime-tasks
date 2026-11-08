#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import math
import os
import random
import secrets
import subprocess
import tempfile
import pytest
from pathlib import Path

DETECTOR_SCRIPT = "/home/user/detector.py"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
THRESHOLD = 0.0000000005

def test_detector_script_exists():
    assert os.path.isfile(DETECTOR_SCRIPT), f"Detector script not found at {DETECTOR_SCRIPT}"

def run_detector(filepath):
    result = subprocess.run(
        ["python3", DETECTOR_SCRIPT, str(filepath)],
        capture_output=True,
        text=True,
        timeout=5
    )
    return result.stdout.strip()

def test_evil_corpus():
    evil_files = list(Path(EVIL_CORPUS_DIR).glob("*.json"))
    assert len(evil_files) > 0, f"No json files found in {EVIL_CORPUS_DIR}"

    bypassed = []
    for filepath in evil_files:
        output = run_detector(filepath)
        if output != "EVIL":
            bypassed.append((filepath.name, output))

    if bypassed:
        details = ", ".join([f"{f} (output: {o})" for f, o in bypassed])
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed. Offending files: {details}")

def test_clean_corpus():
    clean_files = list(Path(CLEAN_CORPUS_DIR).glob("*.json"))
    assert len(clean_files) > 0, f"No json files found in {CLEAN_CORPUS_DIR}"

    modified = []
    for filepath in clean_files:
        output = run_detector(filepath)
        if output != "CLEAN":
            modified.append((filepath.name, output))

    if modified:
        details = ", ".join([f"{f} (output: {o})" for f, o in modified])
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean modified/flagged. Offending files: {details}")

def expected_classification(data):
    correct = math.fsum(data)
    buggy = 0.0
    for value in data:
        buggy += value
    return "EVIL" if abs(correct - buggy) > THRESHOLD else "CLEAN"

def test_generated_unseen_inputs():
    rng = random.SystemRandom()
    cases = []

    # Exercise the strict threshold boundary and both sides of it with
    # unpredictable magnitudes, signs, and ordering.
    for factor in (0.1, 0.5, 1.0, 1.01, 2.0, 10.0, 1000.0):
        for _ in range(5):
            large = 10.0 ** rng.randint(8, 16)
            delta = THRESHOLD * factor * rng.choice((-1.0, 1.0))
            form = rng.randrange(4)
            if form == 0:
                data = [large, delta, -large]
            elif form == 1:
                data = [-large, delta, large]
            elif form == 2:
                data = [large, -large, delta]
            else:
                pieces = [delta * rng.random() for _ in range(rng.randint(2, 8))]
                scale = delta / math.fsum(pieces) if math.fsum(pieces) != 0.0 else 1.0
                pieces = [x * scale for x in pieces]
                data = [large] + pieces + [-large]
            cases.append(data)

    # Add varied, non-template inputs so classification cannot be inferred from
    # a particular catastrophic-cancellation triple.
    for _ in range(65):
        length = rng.randint(3, 250)
        scale = 10.0 ** rng.randint(-8, 13)
        data = [rng.uniform(-scale, scale) for _ in range(length)]
        if rng.random() < 0.6:
            large = 10.0 ** rng.randint(8, 16)
            insert_at = rng.randrange(len(data) + 1)
            data[insert_at:insert_at] = [large, rng.uniform(-1e-7, 1e-7), -large]
        cases.append(data)

    expected = [expected_classification(data) for data in cases]
    assert "EVIL" in expected and "CLEAN" in expected

    order = list(range(len(cases)))
    rng.shuffle(order)
    failures = []
    with tempfile.TemporaryDirectory(prefix="detector-unseen-") as temp_dir:
        for index in order:
            path = Path(temp_dir) / f"{secrets.token_hex(12)}.json"
            path.write_text(json.dumps(cases[index]))
            output = run_detector(path)
            if output != expected[index]:
                failures.append((path.name, expected[index], output))

    if failures:
        details = ", ".join(
            f"{name} (expected: {wanted}, output: {actual})"
            for name, wanted, actual in failures[:10]
        )
        pytest.fail(f"{len(failures)} generated cases misclassified: {details}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
