#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def get_wasserstein_distance_equal_size(a, b):
    a_sorted = sorted(a)
    b_sorted = sorted(b)
    n = len(a_sorted)
    return sum(abs(x - y) for x, y in zip(a_sorted, b_sorted)) / n

def test_wasserstein_txt_exists_and_correct():
    result_path = "/home/user/wasserstein.txt"
    fasta_path = "/home/user/sequences.fasta"

    assert os.path.exists(result_path), f"The output file {result_path} does not exist."
    assert os.path.isfile(result_path), f"The path {result_path} is not a file."

    # Compute expected value
    aas = "ACDEFGHIKLMNPQRSTVWY"
    aa_map = {aa: i+1 for i, aa in enumerate(aas)}

    group_a = []
    group_b = []

    with open(fasta_path, "r") as f:
        lines = f.read().strip().split('\n')

    for i in range(0, len(lines), 2):
        if not lines[i].startswith(">"):
            continue
        header = lines[i].strip()
        seq = lines[i+1].strip()

        arr = [aa_map.get(c, 0) for c in seq]
        smoothed = [(arr[j] + arr[j+1] + arr[j+2])/3.0 for j in range(len(arr)-2)]
        m = max(smoothed)

        if "GroupA" in header:
            group_a.append(m)
        elif "GroupB" in header:
            group_b.append(m)

    # Calculate exact distance (assuming equal sizes for the generated groups)
    expected_dist = get_wasserstein_distance_equal_size(group_a, group_b)
    expected_str = f"{expected_dist:.4f}"

    with open(result_path, "r") as f:
        student_ans = f.read().strip()

    assert student_ans == expected_str, f"Expected {expected_str} in {result_path}, but found '{student_ans}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
