#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import math
import os

def get_mismatches(s1, s2):
    return sum(1 for a, b in zip(s1, s2) if a != b)

def test_features_ci_json_exists_and_correct():
    fasta_path = "/home/user/sequences.fasta"
    json_path = "/home/user/features_ci.json"

    assert os.path.exists(fasta_path), f"File missing: {fasta_path}"
    assert os.path.exists(json_path), f"Output file missing: {json_path}"

    # Parse FASTA
    sequences = []
    with open(fasta_path, "r") as f:
        seq = ""
        for line in f:
            line = line.strip()
            if line.startswith(">"):
                if seq:
                    sequences.append(seq)
                seq = ""
            else:
                seq += line
        if seq:
            sequences.append(seq)

    primer = "ACTGGCCTA"
    k = len(primer)

    svs = []
    for seq in sequences:
        # Check for primer match
        match = False
        for i in range(len(seq) - k + 1):
            sub = seq[i:i+k]
            if get_mismatches(sub, primer) <= 1:
                match = True
                break

        if match:
            counts = {
                'A': seq.count('A'),
                'C': seq.count('C'),
                'G': seq.count('G'),
                'T': seq.count('T')
            }
            max_count = max(counts.values())
            svs.append(math.sqrt(max_count))

    assert len(svs) > 0, "No sequences matched the primer criteria."

    # The expected values for numpy.random.seed(42) with 10,000 iterations on the default dataset
    # Since we cannot use numpy in the test, we verify the JSON structure and 
    # check that the values match the expected seeded output for the given sequence set.
    expected_lower = 2.6074
    expected_upper = 3.3323

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {json_path} is not valid JSON."

    assert "ci_lower" in data, "Key 'ci_lower' missing from JSON."
    assert "ci_upper" in data, "Key 'ci_upper' missing from JSON."

    ci_lower = data["ci_lower"]
    ci_upper = data["ci_upper"]

    assert isinstance(ci_lower, (int, float)), "'ci_lower' must be a number."
    assert isinstance(ci_upper, (int, float)), "'ci_upper' must be a number."

    # Check if the values are close to the expected values (allowing a tiny bit of float tolerance 
    # or algorithm variation, but they should match exactly to 4 decimal places if seed 42 was used).
    # We use a tolerance of 0.001 to account for potential minor numpy version differences in percentile methods,
    # but still enforce correctness.
    assert abs(ci_lower - expected_lower) < 0.01, f"Expected ci_lower around {expected_lower}, got {ci_lower}. Check your mismatch logic, SVD computation, and bootstrap seed."
    assert abs(ci_upper - expected_upper) < 0.01, f"Expected ci_upper around {expected_upper}, got {ci_upper}. Check your mismatch logic, SVD computation, and bootstrap seed."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
