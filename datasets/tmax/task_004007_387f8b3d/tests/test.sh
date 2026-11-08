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

INT64_MIN = -(1 << 63)
INT64_MAX = (1 << 63) - 1


def run_script(path, argument, timeout=5):
    return subprocess.run(
        ["bash", path, argument],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )


def assert_detector_result(detector_path, input_path, expected):
    result = run_script(detector_path, input_path)
    assert result.returncode == expected, (
        f"Detector returned {result.returncode} for {input_path}; expected {expected}."
    )
    assert result.stdout == b"", f"Detector wrote to stdout for {input_path}: {result.stdout!r}"
    assert result.stderr == b"", f"Detector wrote to stderr for {input_path}: {result.stderr!r}"


def test_transcript_created_and_correct():
    transcript_path = "/home/user/transcript.txt"
    assert os.path.isfile(transcript_path), f"Transcript file {transcript_path} is missing."
    assert not os.path.islink(transcript_path), "Transcript must be a regular recovered artifact, not a symlink."

    with open(transcript_path, "rb") as f:
        content = f.read()

    expected = b"Use seed four two nine four nine six seven two nine five and set the boundary constraint to negative one.\n"
    assert content == expected, "Transcript is not an exact transcription of the intercepted voicenote."


def test_fuzzer_recovered():
    fuzzer_path = "/home/user/fuzzer.sh"
    assert os.path.isfile(fuzzer_path), f"Recovered fuzzer script {fuzzer_path} is missing."
    assert not os.path.islink(fuzzer_path), "Recovered fuzzer must be a regular file, not a symlink."

    expected = (
        b"#!/bin/bash\n"
        b"SEED=$1\n"
        b"BOUNDARY=$2\n"
        b"echo \"Fuzzing with $SEED and $BOUNDARY\"\n"
    )
    with open(fuzzer_path, "rb") as f:
        recovered = f.read()
    assert recovered == expected, "fuzzer.sh is not the deleted script from the workspace image."

    result = subprocess.run(
        ["bash", fuzzer_path, "4294967295", "-1"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    assert result.returncode == 0
    assert result.stdout == b"Fuzzing with 4294967295 and -1\n"
    assert result.stderr == b""


def test_detector_adversarial_corpus():
    detector_path = "/home/user/detector.sh"
    assert os.path.isfile(detector_path), f"Detector script {detector_path} is missing."
    assert not os.path.islink(detector_path), "Detector must be a regular Bash script, not a symlink."

    evil_dir = "/app/corpus/evil"
    clean_dir = "/app/corpus/clean"

    evil_files = [f for f in glob.glob(os.path.join(evil_dir, "*")) if os.path.isfile(f)]
    clean_files = [f for f in glob.glob(os.path.join(clean_dir, "*")) if os.path.isfile(f)]

    assert len(evil_files) > 0, f"No files found in evil corpus directory {evil_dir}."
    assert len(clean_files) > 0, f"No files found in clean corpus directory {clean_dir}."

    bypassed_evil = []
    for evil_file in evil_files:
        try:
            assert_detector_result(detector_path, evil_file, 1)
        except AssertionError:
            bypassed_evil.append(os.path.basename(evil_file))

    modified_clean = []
    for clean_file in clean_files:
        try:
            assert_detector_result(detector_path, clean_file, 0)
        except AssertionError:
            modified_clean.append(os.path.basename(clean_file))

    error_msgs = []
    if bypassed_evil:
        error_msgs.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        error_msgs.append(f"{len(modified_clean)} of {len(clean_files)} clean rejected or produced output: {', '.join(modified_clean)}")
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_detector_hidden_randomized_corpus():
    detector_path = "/home/user/detector.sh"
    assert os.path.isfile(detector_path), f"Detector script {detector_path} is missing."

    rng = secrets.SystemRandom()
    cases = []

    clean_pairs = {
        (0, 0),
        (0, INT64_MIN),
        (INT64_MAX, 1),
        (INT64_MIN, 1),
        (INT64_MAX, -1),
        (-1, INT64_MAX),
        (3037000499, 3037000499),
        (-3037000499, 3037000499),
    }
    while len(clean_pairs) < 120:
        if rng.randrange(2):
            a = rng.randint(-4_000_000_000, 4_000_000_000)
            b = rng.randint(-2_000_000_000, 2_000_000_000)
        else:
            a = rng.randint(INT64_MIN, INT64_MAX)
            b = rng.choice([-1, 0, 1])
        product = a * b
        if INT64_MIN <= product <= INT64_MAX:
            clean_pairs.add((a, b))

    evil_pairs = {
        (10_000_000_000, 10_000_000_000),
        (INT64_MAX, 2),
        (INT64_MIN, -1),
        (INT64_MIN, 2),
        (-4_000_000_000, 4_000_000_000),
        (-4_000_000_000, -4_000_000_000),
    }
    while len(evil_pairs) < 120:
        a = rng.randint(1 << 31, INT64_MAX)
        b = rng.randint(2, INT64_MAX)
        if rng.randrange(2):
            a = -a
        if rng.randrange(2):
            b = -b
        product = a * b
        if product < INT64_MIN or product > INT64_MAX:
            evil_pairs.add((a, b))

    for pair in clean_pairs:
        cases.append((pair, 0))
    for pair in evil_pairs:
        cases.append((pair, 1))
    rng.shuffle(cases)

    corpus_dir = tempfile.mkdtemp(prefix="sequence-check-")
    try:
        materialized = []
        for (a, b), expected in cases:
            name = secrets.token_hex(16)
            path = os.path.join(corpus_dir, name)
            with open(path, "w", encoding="ascii") as f:
                f.write(f"{a} {b}\n")
            materialized.append((path, expected))

        for path, expected in materialized:
            assert_detector_result(detector_path, path, expected)
    finally:
        shutil.rmtree(corpus_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
