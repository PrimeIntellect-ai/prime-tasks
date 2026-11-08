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

BINARY_PATH = "/home/user/triage_logs"


def test_triage_logs_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"Missing binary file: {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary file is not executable: {BINARY_PATH}"


def test_adversarial_corpus():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_dir), f"Missing clean corpus directory: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Missing evil corpus directory: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".csv")]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".csv")]

    assert len(clean_files) > 0, "No clean files found"
    assert len(evil_files) > 0, "No evil files found"

    clean_failures = []
    evil_failures = []

    for fpath in clean_files:
        result = subprocess.run([BINARY_PATH, fpath], capture_output=True, text=True)
        output = result.stdout.strip()
        if result.returncode != 0 or output != "CLEAN":
            clean_failures.append((os.path.basename(fpath), result.returncode, output))

    for fpath in evil_files:
        result = subprocess.run([BINARY_PATH, fpath], capture_output=True, text=True)
        output = result.stdout.strip()
        if result.returncode != 1 or output != "EVIL":
            evil_failures.append((os.path.basename(fpath), result.returncode, output))

    error_msg = []
    if clean_failures:
        error_msg.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected.")
        for name, code, out in clean_failures:
            error_msg.append(f"  - {name} (code: {code}, output: {out})")

    if evil_failures:
        error_msg.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed.")
        for name, code, out in evil_failures:
            error_msg.append(f"  - {name} (code: {code}, output: {out})")

    if error_msg:
        pytest.fail("\n".join(error_msg))


def test_runtime_generated_inputs_at_unlabelled_paths():
    rng = random.SystemRandom()
    datasets = [
        [1e-6, 1e-4, 0.0, -2e-5, 0.25],
        [rng.uniform(1.000001e-6, 9.999999e-5), 0.2, -0.2],
        [rng.uniform(0.2, 1.0) for _ in range(127)],
        [rng.uniform(0.2, 1.0) for _ in range(126)] + [rng.uniform(2e-6, 9.9e-5)],
    ]

    for _ in range(12):
        values = [rng.uniform(0.0002, 2.0) for _ in range(rng.randint(40, 160))]
        if secrets.randbits(1):
            values.insert(rng.randrange(len(values) + 1), rng.uniform(1.000001e-6, 9.999999e-5))
        else:
            values.extend([1e-6, 1e-4, -rng.uniform(1e-6, 1.0)])
        datasets.append(values)

    rng.shuffle(datasets)

    with tempfile.TemporaryDirectory(prefix="triage-check-") as temp_dir:
        jobs = []
        for values in datasets:
            rng.shuffle(values)
            path = os.path.join(temp_dir, secrets.token_hex(16) + ".csv")
            with open(path, "w", encoding="ascii") as stream:
                for value in values:
                    stream.write(format(value, ".17g") + "\n")
            expected_evil = any(1e-6 < value < 1e-4 for value in values)
            jobs.append((path, expected_evil))

        rng.shuffle(jobs)
        for path, expected_evil in jobs:
            result = subprocess.run(
                [BINARY_PATH, os.path.abspath(path)],
                capture_output=True,
                text=True,
                timeout=10,
            )
            expected_code = 1 if expected_evil else 0
            expected_output = "EVIL" if expected_evil else "CLEAN"
            assert result.returncode == expected_code, (
                f"Wrong exit code for generated input: expected {expected_code}, "
                f"got {result.returncode}; stdout={result.stdout!r}"
            )
            assert result.stdout.strip() == expected_output, (
                f"Wrong output for generated input: expected {expected_output!r}, "
                f"got {result.stdout!r}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
