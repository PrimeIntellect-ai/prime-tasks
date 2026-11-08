#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import secrets
import shutil
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/filter.sh"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"

def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"

def test_filter_behavior():
    # Ensure script exists before running tests
    if not os.path.isfile(SCRIPT_PATH) or not os.access(SCRIPT_PATH, os.X_OK):
        pytest.fail("Filter script is missing or not executable.")

    # Collect clean files
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.fasta')]
    assert len(clean_files) > 0, "No clean FASTA files found to test against."

    # Collect evil files
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.fasta')]
    assert len(evil_files) > 0, "No evil FASTA files found to test against."

    clean_failures = []
    for fname in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, fname)
        result = subprocess.run([SCRIPT_PATH, filepath], capture_output=True)
        if result.returncode != 0:
            clean_failures.append(fname)

    evil_failures = []
    for fname in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, fname)
        result = subprocess.run([SCRIPT_PATH, filepath], capture_output=True)
        if result.returncode != 1:
            evil_failures.append(fname)

    errors = []
    if evil_failures:
        errors.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        errors.append(f"{len(clean_failures)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failures)}")

    if errors:
        pytest.fail(" | ".join(errors))

def expected_status(filepath):
    with open(filepath, "r", encoding="utf-8", newline="") as fasta:
        for raw_line in fasta:
            line = raw_line.rstrip("\r\n")
            if line.startswith(">"):
                continue
            if any(character not in "ACGT" for character in line):
                return 1
    return 0

def test_generated_fasta_inputs():
    if not os.path.isfile(SCRIPT_PATH) or not os.access(SCRIPT_PATH, os.X_OK):
        pytest.fail("Filter script is missing or not executable.")

    rng = random.SystemRandom()
    case_dir = tempfile.mkdtemp(prefix="fasta_probe_", dir="/tmp")
    cases = []
    invalid_characters = ["N", "a", " ", "1", "X", "-", "\t", "?"]

    try:
        # Generate fresh files in one neutrally named directory. Their random
        # filenames do not reveal the expected classification.
        for should_mutate in ([False] * 12 + [True] * 18):
            line_count = rng.randint(1, 5)
            lines = [
                "".join(rng.choice("ACGT") for _ in range(rng.randint(1, 30)))
                for _ in range(line_count)
            ]
            if should_mutate:
                line_index = rng.randrange(len(lines))
                position = rng.randrange(len(lines[line_index]) + 1)
                bad = rng.choice(invalid_characters)
                lines[line_index] = (
                    lines[line_index][:position] + bad + lines[line_index][position:]
                )

            filepath = os.path.join(case_dir, secrets.token_hex(12) + ".fasta")
            # Invalid-looking characters in the header must be ignored.
            header = ">sample N lowercase a spaces 123 " + secrets.token_hex(4)
            with open(filepath, "w", encoding="utf-8", newline="\n") as fasta:
                fasta.write(header + "\n")
                fasta.write("\n".join(lines) + "\n")
            cases.append(filepath)

        rng.shuffle(cases)
        expected = {filepath: expected_status(filepath) for filepath in cases}
        assert set(expected.values()) == {0, 1}, "Generated tests must include both classes"

        failures = []
        for filepath in cases:
            try:
                result = subprocess.run(
                    [SCRIPT_PATH, filepath], capture_output=True, timeout=5
                )
                actual = result.returncode
            except subprocess.TimeoutExpired:
                failures.append(f"{os.path.basename(filepath)} timed out")
                continue

            if actual != expected[filepath]:
                failures.append(
                    f"{os.path.basename(filepath)} expected {expected[filepath]}, got {actual}"
                )

        if failures:
            pytest.fail("Generated FASTA classification failures: " + "; ".join(failures))
    finally:
        shutil.rmtree(case_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
