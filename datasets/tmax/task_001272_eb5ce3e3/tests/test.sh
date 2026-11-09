#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import secrets
import subprocess

import pytest


def test_sync_events_extracted():
    output_file = "/home/user/sync_events.txt"
    assert os.path.exists(output_file), f"Output file missing: {output_file}"

    with open(output_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = ["2.50", "4.20", "8.80"]
    assert lines == expected, f"Expected timestamps {expected}, but got {lines} in {output_file}"


def test_anomaly_detector_executable():
    script_path = "/home/user/detect_anomaly.sh"
    assert os.path.exists(script_path), f"Script missing: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"


def test_adversarial_corpus():
    script_path = "/home/user/detect_anomaly.sh"

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*.log"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.log"))

    assert len(clean_files) > 0, f"No clean corpus files found in {clean_dir}."
    assert len(evil_files) > 0, f"No evil corpus files found in {evil_dir}."

    clean_failures = []
    for cf in clean_files:
        result = subprocess.run([script_path, cf], capture_output=True)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(cf))

    evil_failures = []
    for ef in evil_files:
        result = subprocess.run([script_path, ef], capture_output=True)
        if result.returncode != 1:
            evil_failures.append(os.path.basename(ef))

    errors = []
    if evil_failures:
        errors.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        errors.append(f"{len(clean_failures)} of {len(clean_files)} clean modified: {', '.join(clean_failures)}")

    if errors:
        pytest.fail(" | ".join(errors))


def has_three_cycle(records):
    by_timestamp = {}
    for timestamp, source, destination, _latency in records:
        by_timestamp.setdefault(timestamp, set()).add((source, destination))

    for edges in by_timestamp.values():
        outgoing = {}
        for source, destination in edges:
            outgoing.setdefault(source, set()).add(destination)
        for first, seconds in outgoing.items():
            for second in seconds:
                if second == first:
                    continue
                for third in outgoing.get(second, ()):
                    if third != first and third != second and first in outgoing.get(third, ()):
                        return True
    return False


def make_runtime_case(rng, anomalous):
    prefix = secrets.token_hex(6)
    nodes = [f"N_{prefix}_{i}" for i in range(9)]
    records = []
    timestamps = rng.sample(range(1000, 900000), 4)

    # Populate each window with a randomized DAG. This creates substantial clean
    # traffic, including two-edge paths, without accidentally introducing cycles.
    for timestamp in timestamps:
        ordering = nodes[:6]
        rng.shuffle(ordering)
        for left in range(len(ordering)):
            for right in range(left + 1, len(ordering)):
                if rng.random() < 0.32:
                    records.append((timestamp, ordering[left], ordering[right], rng.randint(1, 999)))

    a, b, c = nodes[6:9]
    if anomalous:
        timestamp = rng.choice(timestamps)
        records.extend([
            (timestamp, a, b, rng.randint(1, 999)),
            (timestamp, b, c, rng.randint(1, 999)),
            (timestamp, c, a, rng.randint(1, 999)),
        ])
    else:
        # The same three edges are present, but in distinct timestamp windows.
        records.extend([
            (timestamps[0], a, b, rng.randint(1, 999)),
            (timestamps[1], b, c, rng.randint(1, 999)),
            (timestamps[2], c, a, rng.randint(1, 999)),
        ])

    rng.shuffle(records)
    return records


def test_runtime_generated_classifier_cases(tmp_path):
    script_path = "/home/user/detect_anomaly.sh"
    rng = random.SystemRandom()
    cases = []

    for anomalous in ([False] * 20 + [True] * 20):
        records = make_runtime_case(rng, anomalous)
        expected = 1 if has_three_cycle(records) else 0
        assert expected == (1 if anomalous else 0), "Verifier case generation error"

        path = tmp_path / f"trace_{secrets.token_hex(12)}.dat"
        path.write_text("".join(
            f"{timestamp} {source} {destination} {latency}\n"
            for timestamp, source, destination, latency in records
        ))
        cases.append((path, expected))

    rng.shuffle(cases)
    failures = []
    for path, expected in cases:
        result = subprocess.run(
            [script_path, str(path)],
            capture_output=True,
            timeout=5,
        )
        if result.returncode != expected:
            failures.append(
                f"{path.name}: expected exit {expected}, got {result.returncode}"
            )

    assert not failures, "Runtime-generated classifier failures: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
