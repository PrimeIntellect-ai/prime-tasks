#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/check_analyze_ast.go
package main

import (
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)

func main() {
    f, err := parser.ParseFile(token.NewFileSet(), "/home/user/analyze.go", nil, 0)
    if err != nil {
        os.Exit(1)
    }

    hasGo := false
    hasSync := false
    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.GoStmt:
            hasGo = true
        case *ast.ChanType:
            hasSync = true
        case *ast.SelectorExpr:
            if id, ok := x.X.(*ast.Ident); ok && id.Name == "sync" && x.Sel.Name == "WaitGroup" {
                hasSync = true
            }
        }
        return true
    })

    if !hasGo || !hasSync {
        os.Exit(1)
    }
}
GO_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import subprocess
import pytest


def read_fasta(path):
    seqs = {}
    with open(path, "r") as f:
        curr_id = None
        curr_seq = []
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith('>'):
                if curr_id:
                    seqs[curr_id] = "".join(curr_seq)
                curr_id = line[1:]
                curr_seq = []
            else:
                curr_seq.append(line)
        if curr_id:
            seqs[curr_id] = "".join(curr_seq)
    return seqs


def calc_sum(seq):
    return sum(abs(ord(a) - ord(b)) for a in seq for b in seq)


def test_analyze_go_exists_and_concurrent():
    go_file = "/home/user/analyze.go"
    assert os.path.isfile(go_file), f"Go source file {go_file} is missing."

    with open(go_file, "r") as f:
        content = f.read()

    assert "go " in content, "The Go program does not appear to use the 'go' keyword for goroutines."
    has_waitgroup = "sync.WaitGroup" in content
    has_chan = "chan " in content or "make(chan" in content
    assert has_waitgroup or has_chan, "The Go program does not appear to use sync.WaitGroup or channels for synchronization."

    ast_check = subprocess.run(
        ["go", "run", "/tmp/check_analyze_ast.go"],
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert ast_check.returncode == 0, (
        "The Go syntax tree does not contain both a goroutine statement and "
        "WaitGroup/channel synchronization.\n" + ast_check.stderr
    )


def test_program_compiles_and_generates_results():
    go_file = "/home/user/analyze.go"
    fasta_path = "/home/user/data/proteins.fasta"
    summary_path = "/home/user/summary.csv"
    binary_path = "/tmp/analyze_submission"

    build = subprocess.run(
        ["go", "build", "-o", binary_path, go_file],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert build.returncode == 0, f"analyze.go did not compile:\n{build.stderr}"

    with open(fasta_path, "rb") as f:
        original_fasta = f.read()

    token = secrets.token_hex(8)
    generated = {
        f"Alpha_{token}": "ACDEFGHIKLM",
        f"Delta_{token}": "WYVTSRQPNMLKI",
        f"Gamma_{token}": "MAMAPRTEINSEQ",
        f"Beta_{token}": "GGHHPPAACCTT",
    }
    expected_lines = [
        f"{seq_id},{calc_sum(generated[seq_id])}"
        for seq_id in sorted(generated)
    ]

    test_fasta = []
    for seq_id, seq in generated.items():
        midpoint = len(seq) // 2
        test_fasta.extend([f">{seq_id}", seq[:midpoint], seq[midpoint:]])

    restore_run = None
    try:
        with open(fasta_path, "w") as f:
            f.write("\n".join(test_fasta) + "\n")
        if os.path.exists(summary_path):
            os.remove(summary_path)

        run = subprocess.run(
            [binary_path],
            cwd="/home/user",
            text=True,
            capture_output=True,
            timeout=20,
        )
        assert run.returncode == 0, f"Compiled program failed:\n{run.stderr}"
        assert os.path.isfile(summary_path), "The executed program did not create summary.csv."

        with open(summary_path, "r") as f:
            actual_lines = [line.strip() for line in f if line.strip()]
        assert actual_lines == expected_lines, (
            "The executed program produced incorrect results for verifier-generated input. "
            f"Expected:\n{chr(10).join(expected_lines)}\nActual:\n{chr(10).join(actual_lines)}"
        )
    finally:
        with open(fasta_path, "wb") as f:
            f.write(original_fasta)
        if os.path.exists(summary_path):
            os.remove(summary_path)
        restore_run = subprocess.run(
            [binary_path],
            cwd="/home/user",
            text=True,
            capture_output=True,
            timeout=20,
        )

    assert restore_run.returncode == 0, (
        f"Compiled program failed on the supplied FASTA input:\n{restore_run.stderr}"
    )


def test_summary_csv_correct():
    fasta_path = "/home/user/data/proteins.fasta"
    summary_path = "/home/user/summary.csv"

    assert os.path.isfile(fasta_path), f"FASTA file {fasta_path} is missing."
    assert os.path.isfile(summary_path), f"Output file {summary_path} is missing."

    seqs = read_fasta(fasta_path)
    expected_lines = []
    for seq_id in sorted(seqs.keys()):
        total_sum = calc_sum(seqs[seq_id])
        expected_lines.append(f"{seq_id},{total_sum}")

    with open(summary_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"The contents of {summary_path} do not match the expected output. "
        f"Expected:\n{chr(10).join(expected_lines)}\nActual:\n{chr(10).join(actual_lines)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
