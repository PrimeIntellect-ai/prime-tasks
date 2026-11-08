#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import random
import secrets
import subprocess
import tempfile
import uuid

import pytest


def test_task1_corrupted_frames():
    """Check if corrupted_frames.txt contains the correct frame numbers."""
    target_file = "/home/user/corrupted_frames.txt"
    assert os.path.isfile(target_file), f"Missing {target_file}"

    with open(target_file, "r") as f:
        content = f.read().strip().splitlines()

    expected = ["14", "27", "41"]
    assert content == expected, f"Expected {expected}, but got {content} in {target_file}"


def test_task2_source_exists():
    source_path = "/home/user/sanitizer.c"
    assert os.path.isfile(source_path), f"Missing C source at {source_path}"


def test_task2_sanitizer_executable():
    """Check if the sanitizer executable exists, is executable, and is a native binary."""
    executable_path = "/home/user/sanitizer"
    assert os.path.isfile(executable_path), f"Missing executable at {executable_path}"
    assert os.access(executable_path, os.X_OK), f"File at {executable_path} is not executable"
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "sanitizer must be a compiled native executable"


def test_task2_sanitizer_adversarial_corpus():
    """Run the sanitizer against the original clean and evil corpora."""
    executable_path = "/home/user/sanitizer"
    assert os.path.isfile(executable_path), f"Missing executable at {executable_path}"

    clean_dir = "/app/adversarial/clean"
    evil_dir = "/app/adversarial/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*.csv"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.csv"))

    assert len(clean_files) > 0, "No clean files found."
    assert len(evil_files) > 0, "No evil files found."

    clean_failures = []
    for f in clean_files:
        result = subprocess.run([executable_path, f], capture_output=True)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(f))

    evil_failures = []
    for f in evil_files:
        result = subprocess.run([executable_path, f], capture_output=True)
        if result.returncode != 1:
            evil_failures.append(os.path.basename(f))

    error_msgs = []
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failures)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def compile_submitted_source():
    source_path = "/home/user/sanitizer.c"
    assert os.path.isfile(source_path), f"Missing C source at {source_path}"
    build_dir = tempfile.mkdtemp(prefix="sanitizer-build-")
    output_path = os.path.join(build_dir, "sanitizer_from_source")
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", source_path, "-o", output_path],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"sanitizer.c did not compile:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(output_path) and os.access(output_path, os.X_OK)
    return output_path


def write_csv(path, tokens):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["id", "measurement", "category_token"])
        for i, token in enumerate(tokens, 1):
            writer.writerow([i, f"{secrets.randbelow(10000)}.{secrets.randbelow(1000):03d}", token])


def test_task2_dynamic_content_and_compiled_source():
    """Use unpredictable content at one neutral pathname for both installed and rebuilt binaries."""
    rebuilt_path = compile_submitted_source()
    binaries = ["/home/user/sanitizer", rebuilt_path]

    for executable in binaries:
        no_arg = subprocess.run([executable], capture_output=True, timeout=5)
        two_args = subprocess.run([executable, "one", "two"], capture_output=True, timeout=5)
        assert no_arg.returncode != 0, "sanitizer accepted zero arguments"
        assert two_args.returncode != 0, "sanitizer accepted more than one argument"

    positive = lambda: str(secrets.randbelow(1000000) + 1)
    cases = [
        ([positive(), positive(), positive()], 0),
        ([positive()], 0),
        ([positive(), f"{secrets.randbelow(999) + 1}.0", positive()], 1),
        (["NaN", positive(), positive()], 1),
        ([positive(), "Inf", positive()], 1),
        ([positive(), "0"], 1),
        ([positive(), f"-{secrets.randbelow(999) + 1}", positive()], 1),
        ([positive(), f"{secrets.randbelow(999) + 1}.{secrets.randbelow(98) + 1}", positive()], 1),
    ]
    random.SystemRandom().shuffle(cases)

    neutral_dir = tempfile.mkdtemp(prefix="csv-check-")
    csv_path = os.path.join(neutral_dir, f"shard-{uuid.uuid4().hex}.csv")

    for tokens, expected in cases:
        write_csv(csv_path, tokens)
        for executable in binaries:
            result = subprocess.run([executable, csv_path], capture_output=True, timeout=5)
            assert result.returncode == expected, (
                f"{executable} returned {result.returncode}, expected {expected}, "
                f"for category tokens {tokens}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
