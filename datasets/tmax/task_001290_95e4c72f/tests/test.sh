#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'GO_EOF' > /tmp/check_concurrency.go
package main

import (
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)

func main() {
    if len(os.Args) != 2 {
        os.Exit(1)
    }
    info, err := os.Lstat(os.Args[1])
    if err != nil || !info.Mode().IsRegular() {
        os.Exit(1)
    }
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil || f.Name.Name != "main" {
        os.Exit(1)
    }
    concurrent := false
    ast.Inspect(f, func(n ast.Node) bool {
        if _, ok := n.(*ast.GoStmt); ok {
            concurrent = true
        }
        return true
    })
    if !concurrent {
        os.Exit(1)
    }
}
GO_EOF

cat <<'PY_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import subprocess

FASTA = "/home/user/data/sequences.fasta"
CSV = "/home/user/data/growth_rates.csv"
SOURCE = "/home/user/fit_model.go"
RESULT = "/home/user/model_results.json"


def get_expected_ols():
    seqs = {}
    with open(FASTA, "r") as f:
        current_id = None
        current_seq = []
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if current_id is not None:
                    seqs[current_id] = "".join(current_seq)
                current_id = line[1:].split()[0]
                current_seq = []
            else:
                current_seq.append(line.upper())
        if current_id is not None:
            seqs[current_id] = "".join(current_seq)

    gc_ratios = {}
    for sid, seq in seqs.items():
        g = seq.count("G")
        c = seq.count("C")
        a = seq.count("A")
        t = seq.count("T")
        total = a + c + g + t
        if total > 0:
            gc_ratios[sid] = (g + c) / total

    growth_rates = {}
    with open(CSV, "r") as f:
        for row in csv.reader(f):
            if len(row) >= 2:
                try:
                    growth_rates[row[0]] = float(row[1])
                except ValueError:
                    continue

    pairs = [(gc, growth_rates[sid]) for sid, gc in gc_ratios.items()
             if sid in growth_rates]
    assert pairs, "No valid sequences matched with growth rates."
    x_vals = [p[0] for p in pairs]
    y_vals = [p[1] for p in pairs]
    x_mean = sum(x_vals) / len(x_vals)
    y_mean = sum(y_vals) / len(y_vals)
    cov = sum((x - x_mean) * (y - y_mean)
              for x, y in zip(x_vals, y_vals))
    var = sum((x - x_mean) ** 2 for x in x_vals)
    assert var != 0, "Regression input has zero variance."
    b1 = cov / var
    b0 = y_mean - b1 * x_mean
    return round(b0, 4), round(b1, 4)


def run_and_check():
    if os.path.exists(RESULT):
        os.remove(RESULT)
    subprocess.run(
        ["go", "run", SOURCE],
        cwd="/home/user",
        check=True,
        timeout=60,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    assert os.path.isfile(RESULT), f"The output file {RESULT} does not exist."
    with open(RESULT, "r") as f:
        data = json.load(f)

    assert isinstance(data, dict), "The output JSON must be an object."
    assert "beta_0" in data, "The JSON file is missing the 'beta_0' key."
    assert "beta_1" in data, "The JSON file is missing the 'beta_1' key."
    assert set(data) == {"beta_0", "beta_1"}, "The JSON has unexpected keys."

    expected_b0, expected_b1 = get_expected_ols()
    for key, expected in (("beta_0", expected_b0), ("beta_1", expected_b1)):
        value = data[key]
        assert isinstance(value, (int, float)) and not isinstance(value, bool)
        assert math.isfinite(value), f"{key} must be finite."
        assert math.isclose(value, round(value, 4), rel_tol=0, abs_tol=1e-12), \
            f"{key} was not rounded to 4 decimal places."
        assert math.isclose(value, expected, rel_tol=0, abs_tol=0.0001), \
            f"Expected {key} to be {expected}, but got {value}."


with open(FASTA, "rb") as f:
    old_fasta = f.read()
with open(CSV, "rb") as f:
    old_csv = f.read()
old_result_exists = os.path.isfile(RESULT)
old_result = None
if old_result_exists:
    with open(RESULT, "rb") as f:
        old_result = f.read()

try:
    # Preserve the original verifier's check, but force the submitted program
    # to produce the result rather than trusting a pre-created JSON file.
    run_and_check()

    # Exercise the implementation on independently derived data, including a
    # header, lowercase bases, invalid symbols, a zero-valid-base record, an
    # unmatched sequence, and a FASTA description after the sequence ID.
    with open(FASTA, "w") as f:
        f.write(">alpha description text\nacgtNN\n")
        f.write(">beta\nGGGGxxxx\n")
        f.write(">broken\nNN--NN\n")
        f.write(">gamma another description\naattaa\n")
        f.write(">nomatch\ncccc\n")
    with open(CSV, "w", newline="") as f:
        f.write("SequenceID,GrowthRate\n")
        f.write("alpha,2.0\n")
        f.write("beta,5.0\n")
        f.write("broken,999.9\n")
        f.write("gamma,1.0\n")
        f.write("unknown,100.0\n")
    run_and_check()
finally:
    with open(FASTA, "wb") as f:
        f.write(old_fasta)
    with open(CSV, "wb") as f:
        f.write(old_csv)
    if old_result_exists:
        with open(RESULT, "wb") as f:
            f.write(old_result)
    elif os.path.exists(RESULT):
        os.remove(RESULT)
PY_EOF

if go build -o /tmp/check_concurrency /tmp/check_concurrency.go \
   && /tmp/check_concurrency /home/user/fit_model.go \
   && python3 /tmp/test_final_state.py; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
