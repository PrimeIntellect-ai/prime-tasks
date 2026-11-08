#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import secrets
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/detector.sh"


def run_detector(path):
    return subprocess.run(
        ["/bin/bash", SCRIPT_PATH, path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=5,
    ).returncode


def checksum(record_id, uptime, load_a, load_b):
    return (record_id + uptime + math.floor(float(load_a)) + math.ceil(float(load_b))) % 100


def line(record_id, uptime, load_a, load_b, forced_checksum=None):
    value = checksum(record_id, uptime, load_a, load_b) if forced_checksum is None else forced_checksum
    return f"[{record_id}] {uptime} | {load_a}:{load_b} | {value}"


def test_downtime_frames():
    """Test that the downtime frames are correctly identified and written."""
    path = "/home/user/downtime_frames.txt"
    assert os.path.exists(path), f"File {path} does not exist. You must create it with the downtime frame indices."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_frames = ["150", "151", "152", "153", "154", "155"]
    assert lines == expected_frames, f"Expected frames {expected_frames}, but got {lines} in {path}"


def test_detector_script():
    """Retain the checks against the supplied corpus."""
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a regular file."

    clean_dir = "/app/telemetry_corpus/clean/"
    evil_dir = "/app/telemetry_corpus/evil/"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_modified = []
    for cf in clean_files:
        if run_detector(cf) != 0:
            clean_modified.append(os.path.basename(cf))

    evil_bypassed = []
    for ef in evil_files:
        if run_detector(ef) != 1:
            evil_bypassed.append(os.path.basename(ef))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")

    if errors:
        pytest.fail(" | ".join(errors))


def test_detector_generated_corpus():
    """Exercise the detector on randomized, neutrally named telemetry files."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist or is not a regular file."

    rng = random.SystemRandom()
    start = rng.randint(7, 5000)
    uptimes = [rng.randint(40, 10000) for _ in range(5)]

    clean_cases = [
        "\n".join([
            line(start, uptimes[0], "12.5", "8.1"),
            line(start + 1, uptimes[1], "-1.5", "4.0"),
            line(start + 2, uptimes[2], "3.0", "-2.1"),
        ]) + "\n",
        line(rng.randint(1, 9000), uptimes[3], "-9.9", "-3.2") + "\n",
        "\n".join([
            line(start + 20, uptimes[1], "0.0", "0.1"),
            line(start + 21, uptimes[4], "99.9", "-10.0"),
        ]) + "\n",
    ]

    seq_id = rng.randint(10, 8000)
    bad_sum_id = rng.randint(10, 8000)
    correct = checksum(bad_sum_id, uptimes[0], "-1.5", "-2.1")
    canonical = line(rng.randint(10, 8000), uptimes[2], "2.4", "3.1")

    evil_cases = [
        # A gap in an otherwise individually valid sequence.
        "\n".join([
            line(seq_id, uptimes[0], "1.2", "2.8"),
            line(seq_id + 2, uptimes[1], "-4.7", "5.0"),
        ]) + "\n",
        # A duplicate ID in an otherwise individually valid sequence.
        "\n".join([
            line(seq_id, uptimes[0], "1.2", "2.8"),
            line(seq_id, uptimes[1], "-4.7", "5.0"),
        ]) + "\n",
        # Incorrect checksum, including negative floor/ceiling operands.
        line(bad_sum_id, uptimes[0], "-1.5", "-2.1", (correct + 1) % 100) + "\n",
        # Forbidden ID and uptime boundaries, with otherwise correct checksums.
        line(0, uptimes[1], "1.1", "2.2") + "\n",
        line(rng.randint(1, 9000), -1, "1.1", "2.2") + "\n",
        # Strict-format violations.
        canonical.replace("] ", "]  ", 1) + "\n",
        canonical.replace("]", "", 1) + "\n",
        canonical.replace(" | ", "  ", 1) + "\n",
        " " + canonical + "\n",
        canonical + " trailing-data\n",
    ]

    cases = [(text, 0) for text in clean_cases] + [(text, 1) for text in evil_cases]
    rng.shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="telemetry-check-") as directory:
        for text, expected in cases:
            path = os.path.join(directory, secrets.token_hex(12))
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.write(text)
            actual = run_detector(path)
            if actual != expected:
                failures.append(f"expected exit {expected}, got {actual} for generated input {text!r}")

    if failures:
        pytest.fail(" | ".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
