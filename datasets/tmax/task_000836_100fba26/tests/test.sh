#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import secrets
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/analyze_primer.sh"
CLEAN_DIR = "/app/corpus/clean"
EVIL_DIR = "/app/corpus/evil"
MOTIF = "TATAAT"
MIN_GC = 40.0
MAX_GC = 55.0


def run_classifier(path):
    try:
        return subprocess.run(
            [SCRIPT_PATH, path], capture_output=True, timeout=5
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Classifier timed out on {path}")


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."


def test_adversarial_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*.fasta"))
    evil_files = glob.glob(os.path.join(EVIL_DIR, "*.fasta"))

    assert len(clean_files) > 0, "No clean FASTA files found in corpus."
    assert len(evil_files) > 0, "No evil FASTA files found in corpus."

    clean_failures = []
    for f in clean_files:
        if run_classifier(f) != 0:
            clean_failures.append(os.path.basename(f))

    evil_failures = []
    for f in evil_files:
        if run_classifier(f) == 0:
            evil_failures.append(os.path.basename(f))

    errors = []
    if evil_failures:
        errors.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        errors.append(f"{len(clean_failures)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failures)}")

    if errors:
        pytest.fail(" | ".join(errors))


def expected_exit(sequence):
    gc_count = sum(base in "GC" for base in sequence)
    atgc_count = sum(base in "ATGC" for base in sequence)
    gc_percent = 100.0 * gc_count / atgc_count
    clean = MOTIF in sequence and MIN_GC <= gc_percent <= MAX_GC
    return 0 if clean else 1


def sequence_with_motif(rng, length, gc_count):
    assert length >= len(MOTIF)
    assert 0 <= gc_count <= length - len(MOTIF)
    body = [rng.choice("GC") for _ in range(gc_count)]
    body += [rng.choice("AT") for _ in range(length - len(MOTIF) - gc_count)]
    rng.shuffle(body)
    position = rng.randrange(len(body) + 1)
    return "".join(body[:position]) + MOTIF + "".join(body[position:])


def sequence_without_motif(rng, length, gc_count):
    while True:
        sequence = [rng.choice("GC") for _ in range(gc_count)]
        sequence += [rng.choice("AT") for _ in range(length - gc_count)]
        rng.shuffle(sequence)
        sequence = "".join(sequence)
        if MOTIF not in sequence:
            return sequence


def write_fasta(path, sequence, rng):
    widths = []
    remaining = len(sequence)
    while remaining:
        width = rng.randint(1, min(23, remaining))
        widths.append(width)
        remaining -= width

    with open(path, "w", encoding="ascii") as fasta:
        fasta.write(f">held_out_{secrets.token_hex(8)}\n")
        offset = 0
        for width in widths:
            fasta.write(sequence[offset:offset + width] + "\n")
            offset += width


def test_runtime_generated_held_out_sequences():
    rng = random.Random(secrets.randbits(128))
    cases = []

    # Exact inclusive boundaries and immediately-outside values.
    for gc_count in (40, 55, 39, 56):
        cases.append(sequence_with_motif(rng, 100, gc_count))

    # Motif-free sequences must be rejected even when their GC is acceptable.
    for gc_count in (40, 47, 55):
        cases.append(sequence_without_motif(rng, 100, gc_count))

    # Additional unpredictable lengths, contents, motif positions, and GC values.
    for _ in range(30):
        length = rng.randint(48, 220)
        gc_count = rng.randint(0, length - len(MOTIF))
        cases.append(sequence_with_motif(rng, length, gc_count))

    for _ in range(12):
        length = rng.randint(48, 220)
        gc_count = rng.randint(0, length)
        cases.append(sequence_without_motif(rng, length, gc_count))

    rng.shuffle(cases)
    with tempfile.TemporaryDirectory(prefix=f"primer-heldout-{secrets.token_hex(8)}-") as directory:
        failures = []
        for sequence in cases:
            path = os.path.join(directory, f"{secrets.token_hex(12)}.fasta")
            write_fasta(path, sequence, rng)
            expected = expected_exit(sequence)
            actual = run_classifier(path)
            if actual != expected:
                gc_percent = 100.0 * sum(b in "GC" for b in sequence) / len(sequence)
                failures.append(
                    f"expected exit {expected}, got {actual} "
                    f"(length={len(sequence)}, GC={gc_percent:.6f}, motif={MOTIF in sequence})"
                )

        assert not failures, "Held-out classification failures: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
