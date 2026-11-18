#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import secrets
import shutil
import subprocess
import tempfile

import pytest

DETECTOR = "/home/user/detector"
SOURCE = "/home/user/detector.c"
PRIMER = "GACTCGAT"


def run_detector(executable, filepath):
    try:
        return subprocess.run(
            [executable, filepath],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Detector timed out on {filepath}")


def test_detector_exists_and_executable():
    assert os.path.isfile(DETECTOR), f"Detector executable not found at {DETECTOR}"
    assert os.access(DETECTOR, os.X_OK), f"Detector at {DETECTOR} is not executable"


def test_detector_source_exists_and_builds(tmp_path):
    assert os.path.isfile(SOURCE), f"C source not found at {SOURCE}"
    rebuilt = tmp_path / "detector-rebuilt"
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"detector.c did not compile:\n{result.stderr}"


def test_detector_clean_corpus():
    clean_files = glob.glob("/app/corpora/clean/*.fasta")
    assert len(clean_files) > 0, "No clean corpus files found."

    failed_files = []
    for filepath in clean_files:
        if run_detector(DETECTOR, filepath) != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/rejected (expected exit code 0). Offending files: {', '.join(failed_files)}")


def test_detector_evil_corpus():
    evil_files = glob.glob("/app/corpora/evil/*.fasta")
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_files = []
    for filepath in evil_files:
        if run_detector(DETECTOR, filepath) != 1:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed (expected exit code 1). Offending files: {', '.join(failed_files)}")


def write_fasta(path, sequence, rng):
    widths = []
    remaining = len(sequence)
    while remaining:
        width = min(remaining, rng.randint(31, 83))
        widths.append(width)
        remaining -= width

    with open(path, "w") as handle:
        handle.write(">" + secrets.token_hex(12) + "\n")
        offset = 0
        for width in widths:
            handle.write(sequence[offset:offset + width] + "\n")
            offset += width


def make_dynamic_cases(directory):
    rng = random.SystemRandom()
    bases = "ACGT"
    cases = []

    # Fresh safe inputs with neutral, unpredictable paths.
    for _ in range(8):
        length = rng.randint(700, 1300)
        sequence = "".join(rng.choice(bases) for _ in range(length))
        while PRIMER in sequence:
            position = sequence.index(PRIMER)
            replacement = "A" if sequence[position] != "A" else "C"
            sequence = sequence[:position] + replacement + sequence[position + 1:]
        path = os.path.join(directory, secrets.token_hex(16) + ".fasta")
        write_fasta(path, sequence, rng)
        cases.append((path, 0))

    # Fresh triggering inputs, with randomized flanks, lengths, line wrapping,
    # headers, and paths so classification cannot be inferred from a pathname.
    for _ in range(8):
        left = "".join(rng.choice(bases) for _ in range(rng.randint(0, 40)))
        right = "".join(rng.choice(bases) for _ in range(rng.randint(0, 40)))
        sequence = left + PRIMER * rng.randint(100, 160) + right
        path = os.path.join(directory, secrets.token_hex(16) + ".fasta")
        write_fasta(path, sequence, rng)
        cases.append((path, 1))

    rng.shuffle(cases)
    return cases


def test_detector_on_unlabelled_fresh_inputs(tmp_path):
    cases_dir = tmp_path / secrets.token_hex(12)
    cases_dir.mkdir()
    cases = make_dynamic_cases(str(cases_dir))

    rebuilt = tmp_path / (secrets.token_hex(12) + "-bin")
    build = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert build.returncode == 0, f"detector.c did not compile:\n{build.stderr}"

    failures = []
    for executable in (DETECTOR, str(rebuilt)):
        for filepath, expected in cases:
            actual = run_detector(executable, filepath)
            if actual != expected:
                failures.append((os.path.basename(executable), os.path.basename(filepath), expected, actual))

    assert not failures, "Detector failed fresh FASTA cases: " + "; ".join(
        f"{exe} on {name}: expected {expected}, got {actual}"
        for exe, name, expected, actual in failures
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
