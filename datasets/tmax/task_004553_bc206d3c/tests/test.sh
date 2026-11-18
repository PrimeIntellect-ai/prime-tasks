#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import secrets
import subprocess

SCRIPT_PATH = "/home/user/detector.sh"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"


def run_detector(filepath):
    return subprocess.run(
        [SCRIPT_PATH, filepath],
        capture_output=True,
        timeout=10,
    )


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_adversarial_corpus():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*"))
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*"))

    assert len(evil_files) > 0, "No files found in evil corpus directory."
    assert len(clean_files) > 0, "No files found in clean corpus directory."

    evil_bypassed = []
    for filepath in evil_files:
        if not os.path.isfile(filepath):
            continue
        result = run_detector(filepath)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(filepath))

    clean_modified = []
    for filepath in clean_files:
        if not os.path.isfile(filepath):
            continue
        result = run_detector(filepath)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(filepath))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed[:5])}{'...' if len(evil_bypassed) > 5 else ''}")
    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_modified[:5])}{'...' if len(clean_modified) > 5 else ''}")

    assert not error_messages, " | ".join(error_messages)


def make_sequence(kmer_count):
    # Decoy tokens contain many As and Ts but never TATA. Separating every token
    # with C or G prevents motifs from being created across token boundaries.
    decoys = ["AAA", "TTT", "ATTT", "TAAT", "AATT", "TTAA", "T", "A"]
    tokens = ["TATA"] * kmer_count
    tokens += [secrets.choice(decoys) for _ in range(secrets.randbelow(45) + 15)]
    random.SystemRandom().shuffle(tokens)
    sequence = secrets.choice("CG")
    for token in tokens:
        sequence += token + secrets.choice("CG")
    assert sequence.count("TATA") == kmer_count
    return sequence


def write_multiline_fasta(path, sequence):
    # The header deliberately contains many copies of the motif; they must be ignored.
    lines = [">unseen_TATA_TATA_TATA_TATA_TATA_TATA_TATA"]
    pos = 0
    while pos < len(sequence):
        width = secrets.randbelow(17) + 1
        lines.append(sequence[pos:pos + width])
        pos += width
    path.write_text("\n".join(lines) + "\n")


def test_generated_unseen_fasta_inputs(tmp_path):
    # Clean and evil examples share one random directory and opaque random names,
    # so their expected result cannot be inferred from the argument path.
    counts = [0, 1, 3, 4, 5, 5, 6, 6, 7, 9, 11]
    random.SystemRandom().shuffle(counts)

    failures = []
    for count in counts:
        filepath = tmp_path / (secrets.token_hex(12) + ".fa")
        sequence = make_sequence(count)
        write_multiline_fasta(filepath, sequence)

        expected = 1 if sequence.count("TATA") > 5 else 0
        result = run_detector(str(filepath))
        if result.returncode != expected:
            failures.append(
                f"count={count}, expected exit {expected}, got {result.returncode}"
            )

    assert not failures, "Generated FASTA failures: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
