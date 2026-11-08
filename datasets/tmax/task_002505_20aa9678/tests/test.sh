#!/bin/bash
mkdir -p /logs/verifier

run_checks() {
    if [ ! -f /home/user/process.go ] || [ -L /home/user/process.go ]; then
        echo "Missing or invalid /home/user/process.go"
        return 1
    fi

    cat << 'GO_EOF' > /tmp/check_goroutine.go
package main

import (
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)

func main() {
    f, err := parser.ParseFile(token.NewFileSet(), "/home/user/process.go", nil, 0)
    if err != nil {
        os.Exit(1)
    }
    found := false
    ast.Inspect(f, func(n ast.Node) bool {
        if _, ok := n.(*ast.GoStmt); ok {
            found = true
        }
        return true
    })
    if !found {
        os.Exit(1)
    }
}
GO_EOF

    go run /tmp/check_goroutine.go || return 1
    go build -o /tmp/process_submission /home/user/process.go || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import math
import os
import secrets
import shutil
import subprocess

FASTA_PATH = "/home/user/sequences.fasta"
CSV_PATH = "/home/user/divergence_results.csv"
BINARY_PATH = "/tmp/process_submission"


def parse_fasta(path):
    seqs = {}
    current_id = None
    current_seq = []
    with open(path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith('>'):
                if current_id:
                    seqs[current_id] = ''.join(current_seq)
                current_id = line[1:]
                current_seq = []
            else:
                current_seq.append(line)
        if current_id:
            seqs[current_id] = ''.join(current_seq)
    return seqs


def get_dist(seq):
    counts = {''.join(a): 0 for a in itertools.product('ACGT', repeat=3)}
    for i in range(len(seq) - 2):
        kmer = seq[i:i + 3]
        if kmer in counts:
            counts[kmer] += 1
    N = len(seq) - 2
    return {k: (c + 1) / (N + 64) for k, c in counts.items()}


def kl(p, q):
    return sum(p[k] * math.log2(p[k] / q[k]) for k in p)


def random_sequence(length):
    alphabet = "ACGT"
    return ''.join(alphabet[secrets.randbelow(4)] for _ in range(length))


def remove_path(path):
    if not os.path.lexists(path):
        return
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    else:
        os.unlink(path)


def write_fasta(records):
    remove_path(FASTA_PATH)
    with open(FASTA_PATH, "w") as f:
        for sequence_id, sequence in records:
            f.write(f">{sequence_id}\n")
            for offset in range(0, len(sequence), 17):
                f.write(sequence[offset:offset + 17] + "\n")
    os.chown(FASTA_PATH, 0, 0)
    os.chmod(FASTA_PATH, 0o444)
    with open(FASTA_PATH, "rb") as f:
        return f.read()


def check_one_run(records):
    original_fasta = write_fasta(records)

    seqs = parse_fasta(FASTA_PATH)
    assert "Reference" in seqs, "Reference sequence is missing from FASTA."
    ref_seq = seqs.pop("Reference")
    pref = get_dist(ref_seq)

    expected = {}
    for target_id, seq in seqs.items():
        p_target = get_dist(seq)
        expected[target_id] = kl(p_target, pref)

    remove_path(CSV_PATH)
    result = subprocess.run(
        ["runuser", "-u", "user", "--", BINARY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Go program failed with exit code {result.returncode}. "
        f"stdout: {result.stdout} stderr: {result.stderr}"
    )

    assert os.path.exists(CSV_PATH), (
        f"File {CSV_PATH} is missing. The Go program should write its output here."
    )
    assert os.path.isfile(CSV_PATH), f"File {CSV_PATH} is not a regular file."
    assert os.path.exists(FASTA_PATH), f"File {FASTA_PATH} is missing."
    with open(FASTA_PATH, "rb") as f:
        assert f.read() == original_fasta, "The Go program must not alter the input FASTA."

    with open(CSV_PATH, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) > 0, "CSV file is empty."
    assert lines[0] == "SequenceID,KLDivergence", (
        "CSV header is incorrect. Expected 'SequenceID,KLDivergence', "
        f"got '{lines[0]}'"
    )

    parsed_results = {}
    for line in lines[1:]:
        parts = line.split(',')
        assert len(parts) == 2, f"Invalid CSV line: {line}"
        parsed_results[parts[0]] = float(parts[1])

    assert sorted(parsed_results.keys()) == sorted(expected.keys()), (
        "Target IDs in CSV do not match the expected targets from FASTA."
    )

    keys_in_file = [line.split(',')[0] for line in lines[1:]]
    assert keys_in_file == sorted(keys_in_file), (
        "CSV rows are not sorted alphabetically by SequenceID."
    )

    for target_id in expected:
        expected_val = expected[target_id]
        actual_val = parsed_results[target_id]
        line_for_target = [
            line for line in lines[1:] if line.startswith(target_id + ',')
        ][0]
        val_str = line_for_target.split(',')[1]
        assert '.' in val_str and len(val_str.split('.')[1]) == 4, (
            f"Value for {target_id} is not formatted to exactly 4 decimal places: "
            f"{val_str}"
        )
        assert math.isclose(actual_val, expected_val, abs_tol=1e-4), (
            f"KL divergence for {target_id} is incorrect. "
            f"Expected ~{expected_val:.4f}, got {actual_val:.4f}"
        )


def test_divergence_results():
    suffix = secrets.token_hex(4)
    reference = random_sequence(113)
    records = [
        ("Reference", reference),
        (f"Alpha_{suffix}", random_sequence(79)),
        (f"Delta_{suffix}", reference),
        (f"Kappa_{suffix}", "ACGT" * 23 + "AC"),
        (f"Omega_{suffix}", random_sequence(137)),
    ]
    check_one_run(records)

    suffix = secrets.token_hex(4)
    records = [
        ("Reference", random_sequence(91)),
        (f"Beta_{suffix}", "A" * 68),
        (f"Gamma_{suffix}", random_sequence(104)),
        (f"Theta_{suffix}", "ATATCGCG" * 12),
    ]
    check_one_run(records)
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || return 1
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
