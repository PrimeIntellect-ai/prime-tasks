#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import stat
import subprocess
import tempfile

import pytest

EXECUTABLE_PATH = "/home/user/sequence_filter"
SOURCE_PATH = "/home/user/sequence_filter.c"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"


def parse_fasta(path):
    parts = []
    with open(path, "r", newline=None) as f:
        for line in f:
            if line.startswith(">"):
                continue
            parts.append(line.strip())
    return "".join(parts)


def expected_exit(sequence):
    for gap in (1, 2, 3):
        width = 8 + gap
        for i in range(0, len(sequence) - width + 1):
            if sequence[i:i + 4] == "GGGG" and sequence[i + 4 + gap:i + 8 + gap] == "GGGG":
                return 1

    counts = {a + b: 1 for a in "ACGT" for b in "ACGT"}
    for i in range(len(sequence) - 1):
        counts[sequence[i:i + 2]] += 1
    total = sum(counts.values())
    divergence = sum((count / total) * math.log((count / total) / (1.0 / 16.0))
                     for count in counts.values())
    return 1 if divergence > 0.20 else 0


def run_filter(path, timeout=3):
    return subprocess.run([EXECUTABLE_PATH, os.path.abspath(path)],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=timeout).returncode


def test_required_artifacts_exist_and_executable_is_compiled():
    assert os.path.isfile(SOURCE_PATH), f"C source not found at {SOURCE_PATH}"
    assert os.path.isfile(EXECUTABLE_PATH), f"Executable not found at {EXECUTABLE_PATH}"
    st = os.stat(EXECUTABLE_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"File at {EXECUTABLE_PATH} is not executable"
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "sequence_filter must be a compiled executable"


def test_requires_exactly_one_argument():
    no_arg = subprocess.run([EXECUTABLE_PATH], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=3)
    two_args = subprocess.run([EXECUTABLE_PATH, "/dev/null", "/dev/null"],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              timeout=3)
    assert no_arg.returncode != 0
    assert two_args.returncode != 0


def test_shipped_corpus_against_stated_algorithm():
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR)
                  if f.endswith(".fasta")]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR)
                   if f.endswith(".fasta")]
    assert evil_files, f"No evil fasta files found in {EVIL_CORPUS_DIR}"
    assert clean_files, f"No clean fasta files found in {CLEAN_CORPUS_DIR}"

    for path in evil_files + clean_files:
        sequence = parse_fasta(path)
        assert run_filter(path) == expected_exit(sequence), os.path.basename(path)

    # Preserve the original valid evil-corpus assertion.
    for path in evil_files:
        assert run_filter(path) == 1, os.path.basename(path)


def test_unpredictable_fasta_inputs():
    rng = secrets.SystemRandom()
    cases = []

    # Uniformly sampled sequences accepted by the independently computed rule.
    while len(cases) < 18:
        n = rng.randrange(80, 241)
        sequence = "".join(rng.choice("ACGT") for _ in range(n))
        if expected_exit(sequence) == 0:
            cases.append(sequence)

    clean_bases = list(cases[:9])

    # Force each allowed motif gap into otherwise clean random material.
    for gap in (1, 2, 3):
        for _ in range(3):
            base = rng.choice(clean_bases)
            pos = rng.randrange(5, len(base) - (13 + gap))
            middle = "".join(rng.choice("ACGT") for _ in range(gap))
            sequence = base[:pos] + "GGGG" + middle + "GGGG" + base[pos + 8 + gap:]
            assert expected_exit(sequence) == 1
            cases.append(sequence)

    # Highly skewed sequences exercise the KL branch without relying on names.
    while len(cases) < 36:
        n = rng.randrange(60, 201)
        sequence = "".join(rng.choices("ACGT", weights=(82, 6, 6, 6), k=n))
        if expected_exit(sequence) == 1:
            cases.append(sequence)

    # Headers contain misleading sequence-like text and must be ignored.
    cases.extend([
        "ACGT" * 40,
        "A",
        "",
    ])
    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="fasta_inputs_") as directory:
        pending = []
        for index, sequence in enumerate(cases):
            name = secrets.token_hex(12) + ".fasta"
            path = os.path.join(directory, name)
            width = rng.randrange(7, 24)
            newline = "\r\n" if index % 3 == 0 else "\n"
            header = ">" + secrets.token_hex(8) + "_GGGGAGGGG_AAAAAAAAA" + newline
            lines = [sequence[i:i + width] for i in range(0, len(sequence), width)]
            body = newline.join(lines)
            if lines:
                body += newline
            with open(path, "w", newline="") as f:
                f.write(header + body)
            pending.append((path, expected_exit(sequence)))

        rng.shuffle(pending)
        failures = []
        for path, expected in pending:
            actual = run_filter(path)
            if actual != expected:
                failures.append(f"{os.path.basename(path)}: expected {expected}, got {actual}")
        assert not failures, " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
