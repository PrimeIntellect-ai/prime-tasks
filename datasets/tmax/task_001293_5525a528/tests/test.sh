#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess

import pytest

SOURCE = "/home/user/analyze.go"
INPUT = "/home/user/input.fasta"
RESULT = "/home/user/result.txt"
BINARY = "/tmp/submitted_analyze"
ALPHABET = "ACGT"

CANONICAL_FASTA = ">Seq1\nATCGATCGATCGA\n>Seq2\nATCGATTTTTTTT\n>Seq3\nTTTTTGGGGGCCC\n>Seq4\nGGCCCAAAAAAAA\n>Seq5\nAAAAATCGATCGA\n"


def jsd(a, b):
    pa = [a.count(base) / len(a) for base in ALPHABET]
    pb = [b.count(base) / len(b) for base in ALPHABET]
    total = 0.0
    for p, q in zip(pa, pb):
        m = (p + q) / 2.0
        if p > 0:
            total += 0.5 * p * math.log2(p / m)
        if q > 0:
            total += 0.5 * q * math.log2(q / m)
    return total


def expected_result(records):
    edges = []
    for source_id, source_seq in records:
        for target_id, target_seq in records:
            if source_id != target_id and source_seq[-5:] == target_seq[:5]:
                edges.append((jsd(source_seq, target_seq), source_id, target_id))
    if not edges:
        return "None", []
    edges.sort(reverse=True)
    value, source_id, target_id = edges[0]
    return f"{source_id},{target_id},{value:.4f}", edges


def write_fasta(records):
    with open(INPUT, "w") as f:
        for sequence_id, sequence in records:
            f.write(f">{sequence_id}\n{sequence}\n")


def run_submission():
    if os.path.lexists(RESULT):
        if os.path.isdir(RESULT):
            os.rmdir(RESULT)
        else:
            os.remove(RESULT)
    completed = subprocess.run(
        [BINARY], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert completed.returncode == 0, (
        f"analyze.go exited with status {completed.returncode}. "
        f"stdout={completed.stdout!r}, stderr={completed.stderr!r}"
    )
    assert os.path.exists(RESULT), f"Missing required output file: {RESULT}"
    assert os.path.isfile(RESULT), f"Expected a file, but found a directory: {RESULT}"
    with open(RESULT, "r") as f:
        return f.read().strip()


def random_word(length):
    return "".join(secrets.choice(ALPHABET) for _ in range(length))


def make_random_graph_case():
    for _ in range(500):
        tokens = []
        while len(tokens) < 5:
            token = random_word(5)
            if token not in tokens:
                tokens.append(token)

        nonce = secrets.token_hex(6)
        ids = [f"Node_{nonce}_{i}" for i in range(6)]
        sequences = []
        for i in range(6):
            dominant = ALPHABET[i % 4]
            middle = dominant * secrets.randbelow(15) + random_word(8 + secrets.randbelow(10))
            if i == 0:
                sequence = random_word(5) + middle + tokens[0]
            elif i == 5:
                sequence = tokens[4] + middle + random_word(5)
            else:
                sequence = tokens[i - 1] + middle + tokens[i]
            sequences.append(sequence)

        records = list(zip(ids, sequences))
        expected, edges = expected_result(records)
        if len(edges) >= 5 and len(edges) > 1 and edges[0][0] - edges[1][0] > 1e-8:
            return records, expected
    pytest.fail("Could not generate a graph case with a unique maximum JSD")


def test_analyze_go_exists():
    """Check that the Go source file /home/user/analyze.go exists."""
    assert os.path.exists(SOURCE), f"Missing expected Go source file: {SOURCE}"
    assert os.path.isfile(SOURCE), f"Expected a file, but found a directory: {SOURCE}"


def test_result_txt_content_and_program_behavior():
    """Build and execute the submitted program on the original and derived inputs."""
    built = subprocess.run(
        ["go", "build", "-o", BINARY, SOURCE], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert built.returncode == 0, (
        f"Failed to build {SOURCE}. stdout={built.stdout!r}, stderr={built.stderr!r}"
    )
    assert os.path.isfile(BINARY), "Go build did not produce an executable"

    with open(INPUT, "w") as f:
        f.write(CANONICAL_FASTA)
    actual_content = run_submission()
    expected_content = "Seq3,Seq4,0.3698"
    assert actual_content == expected_content, (
        f"Content of {RESULT} is incorrect. Expected '{expected_content}', "
        f"got '{actual_content}'."
    )

    records, expected = make_random_graph_case()
    write_fasta(records)
    actual = run_submission()
    assert actual == expected, (
        f"Incorrect result for generated overlap graph. Expected {expected!r}, got {actual!r}"
    )

    no_edge_records = [
        (f"NoEdge_{secrets.token_hex(4)}_A", "AAAAAACCCCC"),
        (f"NoEdge_{secrets.token_hex(4)}_B", "GGGGGGTGTGT"),
        (f"NoEdge_{secrets.token_hex(4)}_C", "TTTTTACACAC"),
    ]
    expected, edges = expected_result(no_edge_records)
    assert not edges and expected == "None"
    write_fasta(no_edge_records)
    actual = run_submission()
    assert actual == expected, f"Expected 'None' for a graph with no edges, got {actual!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
