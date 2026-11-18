#!/bin/bash
set -u
mkdir -p /logs/verifier
ok=1

cat > /tmp/canonical_sequence.fasta <<'EOF'
>sequence_1
ATGCGTACGATCGTAGCTAGCTAGCATCGATCGATCGATCGTACGATCGTAGCTAGCTAGCATCGATCGATCGATCGTACGATCGTAGCTAGCTAGCATCGATCGATCGATC
EOF
chmod 600 /tmp/canonical_sequence.fasta

# The supplied input is part of the task and must not be replaced to trivialize it.
if ! cmp -s /home/user/sequence.fasta /tmp/canonical_sequence.fasta; then
    echo "The supplied sequence.fasta was modified." >&2
    ok=0
fi

if [[ ! -f /home/user/analyze_kmers.sh || -L /home/user/analyze_kmers.sh || ! -x /home/user/analyze_kmers.sh ]]; then
    echo "analyze_kmers.sh is missing, is not a regular script, or is not executable." >&2
    ok=0
fi

cat > /tmp/check_kmer_outputs.py <<'PY'
import os
import sys

fasta_path = sys.argv[1]
with open(fasta_path, "r") as f:
    seq = "".join(line.strip() for line in f if not line.startswith(">"))

transitions = {}
k = 3
for i in range(len(seq) - k):
    pair = (seq[i:i+k], seq[i+1:i+1+k])
    transitions[pair] = transitions.get(pair, 0) + 1

expected_lines = sorted(
    f"{k1} -> {k2} : {count}"
    for (k1, k2), count in transitions.items()
)
ordered = sorted(transitions.items(), key=lambda x: (-x[1], x[0][0], x[0][1]))
expected_top = f"{ordered[0][0][0]}-{ordered[0][0][1]}" if ordered else ""

matrix_path = "/home/user/transition_matrix.txt"
top_path = "/home/user/top_transition.txt"
assert os.path.isfile(matrix_path), f"File {matrix_path} is missing."
assert os.path.isfile(top_path), f"File {top_path} is missing."
with open(matrix_path, "r") as f:
    actual_lines = [line.strip() for line in f if line.strip()]
with open(top_path, "r") as f:
    actual_top = f.read().strip()
assert actual_lines == expected_lines, "transition_matrix.txt is incorrect or not sorted"
assert actual_top == expected_top, f"Expected top transition {expected_top!r}, got {actual_top!r}"
PY
chmod 600 /tmp/check_kmer_outputs.py

run_and_check() {
    cp /home/user/sequence.fasta /tmp/case_sequence.fasta || return 1
    chmod 600 /tmp/case_sequence.fasta
    rm -f /home/user/transition_matrix.txt /home/user/top_transition.txt

    runuser -u user -- bash -c 'cd /home/user && timeout 15s /home/user/analyze_kmers.sh /home/user/sequence.fasta' || return 1

    # Expected answers are based on the pre-execution input, not on a file the
    # submitted script may have modified while running.
    cmp -s /home/user/sequence.fasta /tmp/case_sequence.fasta || return 1
    python3 /tmp/check_kmer_outputs.py /tmp/case_sequence.fasta || return 1
}

if [[ "$ok" -eq 1 ]]; then
    # A crafted tie case verifies alphabetical tie-breaking.
    cat > /home/user/sequence.fasta <<'EOF'
>tie_case
AAACCC
EOF
    chmod 644 /home/user/sequence.fasta
    if ! run_and_check; then
        echo "analyze_kmers.sh failed the tie-case execution test." >&2
        ok=0
    fi
fi

if [[ "$ok" -eq 1 ]]; then
    # Use a fresh, multiline sequence so precomputed output files cannot pass.
    python3 - <<'PY'
import secrets
seq = ''.join(secrets.choice('ACGT') for _ in range(173))
with open('/home/user/sequence.fasta', 'w') as f:
    f.write('>runtime_case\n')
    for i in range(0, len(seq), 29):
        f.write(seq[i:i+29] + '\n')
PY
    chmod 644 /home/user/sequence.fasta
    if ! run_and_check; then
        echo "analyze_kmers.sh failed the runtime-generated execution test." >&2
        ok=0
    fi
fi

# Restore the supplied input and execute the repaired artifact to produce the
# final files checked by the original assertions below.
cp /tmp/canonical_sequence.fasta /home/user/sequence.fasta
chmod 644 /home/user/sequence.fasta
if [[ "$ok" -eq 1 ]] && ! run_and_check; then
    echo "analyze_kmers.sh failed on the supplied sequence." >&2
    ok=0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def get_expected_data():
    fasta_path = "/home/user/sequence.fasta"
    if not os.path.exists(fasta_path):
        pytest.fail(f"Missing {fasta_path}")

    with open(fasta_path, 'r') as f:
        seq = ''.join(line.strip() for line in f if not line.startswith('>'))

    transitions = {}
    k = 3
    for i in range(len(seq) - k):
        k1 = seq[i:i+k]
        k2 = seq[i+1:i+1+k]
        pair = (k1, k2)
        transitions[pair] = transitions.get(pair, 0) + 1

    expected_matrix_lines = []
    for (k1, k2), count in transitions.items():
        expected_matrix_lines.append(f"{k1} -> {k2} : {count}")

    expected_matrix_lines.sort()

    sorted_transitions = sorted(transitions.items(), key=lambda x: (-x[1], x[0][0], x[0][1]))
    if sorted_transitions:
        top_k1, top_k2 = sorted_transitions[0][0]
        expected_top = f"{top_k1}-{top_k2}"
    else:
        expected_top = ""

    return expected_matrix_lines, expected_top

def test_transition_matrix():
    """Check if transition_matrix.txt is correct."""
    matrix_path = "/home/user/transition_matrix.txt"
    assert os.path.isfile(matrix_path), f"File {matrix_path} is missing."

    expected_lines, _ = get_expected_data()

    with open(matrix_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, "The contents of transition_matrix.txt do not match the expected sorted output."

def test_top_transition():
    """Check if top_transition.txt is correct."""
    top_path = "/home/user/top_transition.txt"
    assert os.path.isfile(top_path), f"File {top_path} is missing."

    _, expected_top = get_expected_data()

    with open(top_path, 'r') as f:
        actual_top = f.read().strip()

    assert actual_top == expected_top, f"Expected top transition '{expected_top}', but got '{actual_top}'."
TEST_EOF

if [[ "$ok" -eq 1 ]]; then
    if ! cmp -s /home/user/sequence.fasta /tmp/canonical_sequence.fasta; then
        ok=0
    elif ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
        ok=0
    fi
fi

if [[ "$ok" -eq 1 ]]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
