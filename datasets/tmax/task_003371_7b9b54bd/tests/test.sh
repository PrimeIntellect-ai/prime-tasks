#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import bisect
import math
import os
import random
import secrets
import subprocess
import tempfile

BINARY_PATH = "/home/user/sequence_filter/target/release/sequence_filter"
EVIL_CORPUS = "/app/corpus/evil"
CLEAN_CORPUS = "/app/corpus/clean"
AMINO_ACIDS = "ACDEFGHIKLMNPQRSTVWY"


def test_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"Rust binary not found at {BINARY_PATH}. Did you compile it in release mode?"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable."


def run_classifier(corpus_path):
    result = subprocess.run(
        [BINARY_PATH, corpus_path],
        capture_output=True,
        text=True,
        check=False
    )
    assert result.returncode == 0, f"Binary failed with return code {result.returncode}. Stderr: {result.stderr}"

    output_lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]

    parsed_results = {}
    for line in output_lines:
        parts = line.split(',')
        assert len(parts) == 2, f"Invalid output format: '{line}'. Expected 'filename.fasta,STATUS'"
        filename, status = parts[0].strip(), parts[1].strip()
        parsed_results[filename] = status

    return parsed_results


def test_evil_corpus():
    evil_files = [f for f in os.listdir(EVIL_CORPUS) if f.endswith(".fasta")]
    assert len(evil_files) > 0, "No FASTA files found in evil corpus."

    results = run_classifier(EVIL_CORPUS)

    bypassed = []
    for f in evil_files:
        if f not in results:
            bypassed.append(f"{f} (missing in output)")
        elif results[f] != "EVIL":
            bypassed.append(f"{f} (classified as {results[f]})")

    assert not bypassed, f"{len(bypassed)} of {len(evil_files)} evil files bypassed: {', '.join(bypassed)}"


def test_clean_corpus():
    clean_files = [f for f in os.listdir(CLEAN_CORPUS) if f.endswith(".fasta")]
    assert len(clean_files) > 0, "No FASTA files found in clean corpus."

    results = run_classifier(CLEAN_CORPUS)

    modified = []
    for f in clean_files:
        if f not in results:
            modified.append(f"{f} (missing in output)")
        elif results[f] != "CLEAN":
            modified.append(f"{f} (classified as {results[f]})")

    assert not modified, f"{len(modified)} of {len(clean_files)} clean files modified/rejected: {', '.join(modified)}"


def percentile(values, q):
    values = sorted(values)
    position = (len(values) - 1) * q
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return values[lower]
    fraction = position - lower
    return values[lower] * (1.0 - fraction) + values[upper] * fraction


def reference_ci_width(sequence, seed):
    counts = [sequence.count(amino) for amino in AMINO_ACIDS]
    population = list(range(len(AMINO_ACIDS)))
    rng = random.Random(seed)
    distances = []
    n = len(sequence)

    for _ in range(500):
        sampled = rng.choices(population, weights=counts, k=n)
        sample_counts = [0] * len(AMINO_ACIDS)
        for index in sampled:
            sample_counts[index] += 1
        distance = 0.5 * sum(abs(count / n - 0.05) for count in sample_counts)
        distances.append(distance)

    return percentile(distances, 0.975) - percentile(distances, 0.025)


def make_skewed_sequence(length):
    # Half A; the other half is shared equally by the other 19 amino acids.
    sequence = ["A"] * (length // 2)
    remainder = length - len(sequence)
    for i in range(remainder):
        sequence.append(AMINO_ACIDS[1 + (i % 19)])
    random.SystemRandom().shuffle(sequence)
    return "".join(sequence)


def write_fasta(path, sequence):
    with open(path, "w", encoding="ascii") as handle:
        handle.write(">generated_validation_sequence\n")
        for start in range(0, len(sequence), 71):
            handle.write(sequence[start:start + 71] + "\n")


def run_classifier_strict(corpus_path, expected_files):
    result = subprocess.run(
        [BINARY_PATH, corpus_path],
        capture_output=True,
        text=True,
        check=False,
        timeout=120,
    )
    assert result.returncode == 0, f"Binary failed with return code {result.returncode}. Stderr: {result.stderr}"

    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert len(lines) == len(expected_files), (
        f"Expected exactly {len(expected_files)} output lines, got {len(lines)}: {lines}"
    )

    parsed = {}
    for line in lines:
        parts = line.split(',')
        assert len(parts) == 2, f"Invalid output format: '{line}'. Expected 'filename.fasta,STATUS'"
        filename, status = parts[0].strip(), parts[1].strip()
        assert filename in expected_files, f"Unexpected filename in output: {filename}"
        assert filename not in parsed, f"Duplicate output for {filename}"
        assert status in {"CLEAN", "EVIL"}, f"Invalid status for {filename}: {status}"
        parsed[filename] = status

    assert set(parsed) == set(expected_files), "Output did not contain exactly one result for every FASTA file"
    return parsed


def test_randomized_mixed_corpus_uses_fasta_contents_and_monte_carlo_rule():
    with tempfile.TemporaryDirectory(prefix="sequence_filter_validation_") as corpus:
        short_length = secrets.randbelow(121) + 360
        long_length = secrets.randbelow(8001) + 28000
        constant_length = secrets.randbelow(101) + 150

        sequences = {
            f"{secrets.token_hex(10)}.fasta": make_skewed_sequence(short_length),
            f"{secrets.token_hex(10)}.fasta": make_skewed_sequence(long_length),
            f"{secrets.token_hex(10)}.fasta": "A" * constant_length,
        }

        expected = {}
        widths = {}
        for filename, sequence in sequences.items():
            write_fasta(os.path.join(corpus, filename), sequence)
            width = reference_ci_width(sequence, int.from_bytes(os.urandom(16), "big"))
            widths[filename] = width
            expected[filename] = "EVIL" if width < 0.02 else "CLEAN"

        # These margins ensure implementation RNG and percentile conventions cannot
        # change the expected classifications.
        short_name, long_name, constant_name = list(sequences)
        assert widths[short_name] > 0.04
        assert widths[long_name] < 0.015
        assert widths[constant_name] == 0.0

        actual = run_classifier_strict(corpus, set(sequences))
        assert actual == expected, f"Randomized mixed-corpus results differ from the Monte Carlo rule: expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
