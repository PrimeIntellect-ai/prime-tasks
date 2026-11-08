#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest

EXPECTED_INPUTS = {
    "/home/user/target.seq": b"ATGCATGCATTTTTATGCATGCATTTTTCCCGGGAAATTTTTCCCGGGAAATTTTTCCCGGGAAATTTTTCCCGGGAAATTTTTGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGC",
    "/home/user/background.seq": b"ATGCATGCATTTTTCCCGGGAAATTTTTCCCGGGAAAT",
    "/home/user/candidates.txt": b"ATGCATGCAT\nCCCGGGAAAT\nGCGCGCGCGC\nAAAAATTTTT\n",
}

def read_verified_inputs():
    actual = {}
    for path, expected_content in EXPECTED_INPUTS.items():
        assert os.path.isfile(path), f"Required input fixture {path} is missing or is not a file."
        with open(path, "rb") as f:
            content = f.read()
        assert content == expected_content, f"Required input fixture {path} was modified."
        actual[path] = content.decode("ascii")
    return actual

def compute_expected_optimal_primer():
    inputs = read_verified_inputs()
    target_seq = inputs["/home/user/target.seq"].strip()
    background_seq = inputs["/home/user/background.seq"].strip()
    candidates = [line.strip() for line in inputs["/home/user/candidates.txt"].splitlines() if line.strip()]

    best_primer = None
    best_score = -float('inf')

    for primer in candidates:
        nt = target_seq.count(primer)
        nb = background_seq.count(primer)

        if nt <= nb:
            continue

        gc_count = primer.count('G') + primer.count('C')
        gc_percent = (gc_count / len(primer)) * 100
        penalty = abs(gc_percent - 50)

        score = (nt * 20) - (nb * 5) - penalty

        if score > best_score:
            best_score = score
            best_primer = primer
        elif score == best_score:
            if best_primer is None or primer < best_primer:
                best_primer = primer

    return best_primer, int(best_score) if best_score != -float('inf') else None

def test_input_fixture_integrity():
    """Test that the provided sequences and candidate list were not modified."""
    read_verified_inputs()

def test_optimal_primer_file_exists():
    """Test that the optimal_primer.txt file has been created."""
    assert os.path.isfile("/home/user/optimal_primer.txt"), "The file /home/user/optimal_primer.txt does not exist."

def test_optimal_primer_content():
    """Test that the optimal_primer.txt file contains the correct primer and score."""
    expected = compute_expected_optimal_primer()
    assert expected is not None, "Could not compute expected result due to missing input files."
    expected_primer, expected_score = expected

    with open("/home/user/optimal_primer.txt", "r") as f:
        content = f.read().strip()

    assert content == f"{expected_primer} {expected_score}", f"Expected '{expected_primer} {expected_score}', but found '{content}' in /home/user/optimal_primer.txt"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
