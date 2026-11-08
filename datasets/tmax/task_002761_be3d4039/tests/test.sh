#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
import pytest

DETECTOR_SCRIPT = "/home/user/detector.py"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
MAX_DEPTH = 12


def run_detector(filepath):
    """Run the detector script on a given file and return the exit code."""
    result = subprocess.run(
        ["python3", DETECTOR_SCRIPT, filepath],
        capture_output=True,
        timeout=5
    )
    return result.returncode


def expected_code(payload):
    depth = 0
    maximum = 0
    for char in payload:
        if char == "{":
            depth += 1
            maximum = max(maximum, depth)
        elif char == "}":
            if depth == 0:
                return 1
            depth -= 1
    return 0 if depth == 0 and maximum <= MAX_DEPTH else 1


def test_detector_exists():
    assert os.path.isfile(DETECTOR_SCRIPT), f"The detector script is missing at {DETECTOR_SCRIPT}."


def test_clean_corpus_accepted():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"

    failed_files = []
    total_files = 0
    for filename in sorted(os.listdir(CLEAN_CORPUS_DIR)):
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        if os.path.isfile(filepath):
            total_files += 1
            code = run_detector(filepath)
            if code != 0:
                failed_files.append(filename)

    assert not failed_files, (
        f"{len(failed_files)} of {total_files} clean files modified/rejected (expected exit code 0). "
        f"Offending files: {failed_files}"
    )


def test_evil_corpus_rejected():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    failed_files = []
    total_files = 0
    for filename in sorted(os.listdir(EVIL_CORPUS_DIR)):
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        if os.path.isfile(filepath):
            total_files += 1
            code = run_detector(filepath)
            if code == 0:
                failed_files.append(filename)

    assert not failed_files, (
        f"{len(failed_files)} of {total_files} evil files bypassed detection (expected exit code 1). "
        f"Offending files: {failed_files}"
    )


def test_runtime_generated_payloads():
    rng = random.SystemRandom()
    payloads = []

    # Exercise every depth around the boundary, including the empty payload.
    for depth in range(17):
        payloads.append("{" * depth + "}" * depth)

    # Random brace streams cover premature closes and leftover opens.
    for _ in range(80):
        length = rng.randint(1, 80)
        payloads.append("".join(rng.choice("{}") for _ in range(length)))

    # Varied valid payloads composed of several independently balanced groups.
    for _ in range(30):
        groups = []
        for _ in range(rng.randint(1, 8)):
            depth = rng.randint(1, MAX_DEPTH)
            groups.append("{" * depth + "}" * depth)
        payloads.append("".join(groups))

    # Balanced payloads that exceed the architecture limit.
    for _ in range(20):
        depth = rng.randint(MAX_DEPTH + 1, 35)
        payloads.append("{" * depth + "}" * depth)

    # Explicitly unbalanced payloads in both directions.
    for _ in range(30):
        opens = rng.randint(0, 30)
        closes = rng.randint(0, 30)
        if opens == closes:
            closes += 1
        payloads.append("{" * opens + "}" * closes)

    rng.shuffle(payloads)

    # Every directory contains a mixture of outcomes, so path-name classification
    # cannot substitute for examining the payload.
    with tempfile.TemporaryDirectory(prefix="detector-cases-") as root:
        buckets = ["clean", "evil", secrets.token_hex(6)]
        for bucket in buckets:
            os.mkdir(os.path.join(root, bucket))

        observed = {0: 0, 1: 0}
        for index, payload in enumerate(payloads):
            bucket = buckets[index % len(buckets)]
            filename = secrets.token_hex(12) + ".dat"
            filepath = os.path.join(root, bucket, filename)
            with open(filepath, "w", encoding="ascii") as handle:
                handle.write(payload)

            expected = expected_code(payload)
            observed[expected] += 1
            actual = run_detector(filepath)
            assert actual == expected, (
                f"Detector returned {actual}, expected {expected}, for a runtime-generated "
                f"payload of length {len(payload)}"
            )

        assert observed[0] > 0 and observed[1] > 0
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
