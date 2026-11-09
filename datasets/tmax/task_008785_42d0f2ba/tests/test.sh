#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess

import pytest

EXE = "/home/user/bin/mahalanobis_calc"
CSV = "/home/user/data/kmer_counts.csv"
RESULTS = "/home/user/results.json"
MODULE = "/home/user/src/mahalanobis"

REFERENCE_GO = r'''
package main

import (
    "encoding/csv"
    "encoding/json"
    "log"
    "math/rand"
    "os"
    "sort"
    "strconv"

    "gonum.org/v1/gonum/mat"
    "gonum.org/v1/gonum/stat"
)

type output struct {
    Lower []float64 `json:"lower"`
    Upper []float64 `json:"upper"`
    PValue float64 `json:"p_value"`
}

func main() {
    f, err := os.Open("/home/user/data/kmer_counts.csv")
    if err != nil { log.Fatal(err) }
    defer f.Close()
    records, err := csv.NewReader(f).ReadAll()
    if err != nil { log.Fatal(err) }
    if len(records) != 100 || len(records[0]) == 0 { log.Fatal("unexpected matrix shape") }

    n, p := len(records), len(records[0])
    data := mat.NewDense(n, p, nil)
    for i, row := range records {
        if len(row) != p { log.Fatal("ragged CSV") }
        for j, text := range row {
            v, err := strconv.ParseFloat(text, 64)
            if err != nil { log.Fatal(err) }
            data.Set(i, j, v)
        }
    }

    var cov mat.SymDense
    stat.CovarianceMatrix(&cov, data, nil)
    for i := 0; i < p; i++ {
        cov.SetSym(i, i, cov.At(i, i)+0.0001)
    }
    var inv mat.SymDense
    if err := inv.Inverse(&cov); err != nil { log.Fatal(err) }

    distances := make([]float64, n)
    for i := 0; i < n; i++ {
        d := 0.0
        for j := 0; j < p; j++ {
            for k := 0; k < p; k++ {
                d += data.At(i, j) * inv.At(j, k) * data.At(i, k)
            }
        }
        distances[i] = d
    }

    rng := rand.New(rand.NewSource(42))
    deltas := make([]float64, 10000)
    nonPositive, nonNegative := 0, 0
    for b := 0; b < 10000; b++ {
        a, c := 0.0, 0.0
        for i := 0; i < 50; i++ { a += distances[rng.Intn(50)] }
        for i := 0; i < 50; i++ { c += distances[50+rng.Intn(50)] }
        deltas[b] = a/50.0 - c/50.0
        if deltas[b] <= 0 { nonPositive++ }
        if deltas[b] >= 0 { nonNegative++ }
    }
    sort.Float64s(deltas)
    lo := nonPositive
    if nonNegative < lo { lo = nonNegative }
    pvalue := 2.0 * float64(lo) / 10000.0
    if pvalue > 1 { pvalue = 1 }

    // Include nearby order statistics so standard nearest-rank and interpolated
    // percentile conventions are all accepted.
    result := output{
        Lower: append([]float64(nil), deltas[245:256]...),
        Upper: append([]float64(nil), deltas[9745:9756]...),
        PValue: pvalue,
    }
    if err := json.NewEncoder(os.Stdout).Encode(result); err != nil { log.Fatal(err) }
}
'''


def read_results():
    assert os.path.isfile(RESULTS), f"Results file not found at {RESULTS}"
    with open(RESULTS, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("results.json is not valid JSON")
    expected_keys = {"ci_lower", "ci_upper", "p_value"}
    assert set(data.keys()) == expected_keys, f"results.json must contain exactly keys: {expected_keys}"
    for key in expected_keys:
        assert isinstance(data[key], (int, float)), f"Value for {key} must be a number"
        assert type(data[key]) in (int, float) and math.isfinite(data[key]), f"Value for {key} must be finite"
    return data


def run_target():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    proc = subprocess.run([EXE], cwd="/home/user", text=True, capture_output=True, timeout=45)
    assert proc.returncode == 0, f"mahalanobis_calc failed: {proc.stdout}\n{proc.stderr}"
    return read_results()


def reference_results():
    ref_dir = os.path.join(MODULE, ".verifier_reference")
    os.makedirs(ref_dir, exist_ok=True)
    ref_path = os.path.join(ref_dir, "main.go")
    try:
        with open(ref_path, "w") as f:
            f.write(REFERENCE_GO)
        proc = subprocess.run(
            ["/usr/local/go/bin/go", "run", ref_path],
            cwd=MODULE,
            text=True,
            capture_output=True,
            timeout=60,
        )
        assert proc.returncode == 0, f"Reference calculation failed: {proc.stderr}"
        return json.loads(proc.stdout)
    finally:
        try:
            os.remove(ref_path)
            os.rmdir(ref_dir)
        except OSError:
            pass


def compare_with_reference(actual, expected):
    scale = max(1.0, abs(actual["ci_lower"]), abs(actual["ci_upper"]))
    tol = max(0.002, scale * 2e-6)
    assert min(expected["lower"]) - tol <= actual["ci_lower"] <= max(expected["lower"]) + tol, \
        f"incorrect bootstrap lower confidence bound: {actual['ci_lower']}"
    assert min(expected["upper"]) - tol <= actual["ci_upper"] <= max(expected["upper"]) + tol, \
        f"incorrect bootstrap upper confidence bound: {actual['ci_upper']}"
    assert actual["ci_lower"] <= actual["ci_upper"], "confidence interval bounds are reversed"
    assert 0 <= actual["p_value"] <= 1, "p_value must be between 0 and 1"
    assert abs(actual["p_value"] - expected["p_value"]) <= 0.002, \
        f"incorrect empirical two-sided p-value: {actual['p_value']}"


def test_executable_exists():
    """Check that the compiled Go executable exists."""
    assert os.path.isfile(EXE), f"Executable not found at {EXE}"
    assert os.access(EXE, os.X_OK), f"File at {EXE} is not executable"
    proc = subprocess.run(["/usr/local/go/bin/go", "version", "-m", EXE], text=True, capture_output=True)
    assert proc.returncode == 0 and "go1." in proc.stdout, "mahalanobis_calc is not a compiled Go executable"


def test_executable_computes_requested_statistics():
    """Execute the artifact and compare its output with independently derived answers."""
    with open(CSV, "rb") as f:
        original_csv = f.read()
    try:
        actual = run_target()
        compare_with_reference(actual, reference_results())

        # A second valid, collinear matrix prevents hard-coded results from passing.
        rows = []
        for i in range(100):
            row = []
            for j in range(9):
                base = ((i * (j + 3) + j * j + 7) % 97) / 113.0
                if i < 50:
                    base += 1.75
                row.append(f"{base:.8f}")
            row.append(row[8])
            rows.append(",".join(row))
        with open(CSV, "w") as f:
            f.write("\n".join(rows) + "\n")
        actual = run_target()
        compare_with_reference(actual, reference_results())
    finally:
        with open(CSV, "wb") as f:
            f.write(original_csv)
        # Leave results.json containing results for the instructed input.
        proc = subprocess.run([EXE], cwd="/home/user", text=True, capture_output=True, timeout=45)
        assert proc.returncode == 0, f"mahalanobis_calc failed after restoring input: {proc.stderr}"


def test_results_json_exists_and_format():
    """Check that results.json exists and has the correct format."""
    read_results()


def test_go_code_modified_for_ridge():
    """Check that the Go source code was modified to add 0.0001 to the diagonal."""
    main_go_path = "/home/user/src/mahalanobis/main.go"
    assert os.path.isfile(main_go_path), f"Source file not found at {main_go_path}"
    with open(main_go_path, "r") as f:
        content = f.read()
    assert "0.0001" in content, "Could not find the Ridge regularization constant (0.0001) in main.go"


def test_bootstrap_logic_in_source():
    """Check that bootstrap and seed logic is present in the source directory."""
    src_dir = "/home/user/src/mahalanobis"
    found_seed = False
    found_bootstrap = False
    for root, _, files in os.walk(src_dir):
        for file in files:
            if file.endswith(".go") or file.endswith(".sh") or file.endswith(".py"):
                with open(os.path.join(root, file), "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read()
                    if "42" in content and ("Seed" in content or "seed" in content):
                        found_seed = True
                    if "10000" in content or "10,000" in content:
                        found_bootstrap = True
    assert found_seed, "Could not find seed initialization (e.g., Seed(42)) in the source files."
    assert found_bootstrap, "Could not find 10000 iterations for bootstrap in the source files."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
