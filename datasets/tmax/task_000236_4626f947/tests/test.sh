#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import shutil
import subprocess

import numpy as np
import pytest

GO_FILE = "/home/user/analyze.go"
CSV_FILE = "/home/user/spectra.csv"
JSON_FILE = "/home/user/peak_ci.json"
BINARY = "/tmp/analyze_submission"


@pytest.fixture(scope="session")
def compiled_binary():
    result = subprocess.run(
        ["go", "build", "-o", BINARY, GO_FILE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, f"analyze.go did not compile:\n{result.stdout}"
    assert os.path.isfile(BINARY), "Go build did not produce an executable"
    return BINARY


def test_analyze_go_exists_and_uses_concurrency(compiled_binary):
    """Check that analyze.go exists, compiles, and contains real Go concurrency constructs."""
    assert os.path.exists(GO_FILE), f"The file {GO_FILE} does not exist."
    assert os.path.isfile(GO_FILE), f"{GO_FILE} is not a file."

    with open(GO_FILE, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert re.search(r"\bgo\s+", content), f"No goroutines ('go ' keyword) found in {GO_FILE}."
    assert "sync.WaitGroup" in content or "WaitGroup" in content, f"sync.WaitGroup not found in {GO_FILE}."

    # Parse the source so comments or strings containing those words are not sufficient.
    checker = r'''
package main
import (
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "strconv"
)
func main() {
    if len(os.Args) != 2 { os.Exit(2) }
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil { os.Exit(3) }
    aliases := map[string]bool{}
    dotSync := false
    for _, imp := range f.Imports {
        p, _ := strconv.Unquote(imp.Path.Value)
        if p != "sync" { continue }
        if imp.Name == nil { aliases["sync"] = true
        } else if imp.Name.Name == "." { dotSync = true
        } else if imp.Name.Name != "_" { aliases[imp.Name.Name] = true }
    }
    hasGo, hasWG := false, false
    methods := map[string]bool{"Add": false, "Done": false, "Wait": false}
    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.GoStmt:
            hasGo = true
        case *ast.SelectorExpr:
            if id, ok := x.X.(*ast.Ident); ok && aliases[id.Name] && x.Sel.Name == "WaitGroup" {
                hasWG = true
            }
            if _, ok := methods[x.Sel.Name]; ok { methods[x.Sel.Name] = true }
        case *ast.Ident:
            if dotSync && x.Name == "WaitGroup" { hasWG = true }
        }
        return true
    })
    if !hasGo || !hasWG || !methods["Add"] || !methods["Done"] || !methods["Wait"] { os.Exit(4) }
}
'''
    checker_file = "/tmp/check_go_ast.go"
    with open(checker_file, "w", encoding="utf-8") as f:
        f.write(checker)
    result = subprocess.run(
        ["go", "run", checker_file, GO_FILE],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, "analyze.go must use a real go statement and sync.WaitGroup Add/Done/Wait calls"


def run_submission(binary):
    if os.path.lexists(JSON_FILE):
        os.remove(JSON_FILE)
    result = subprocess.run(
        [binary],
        cwd="/home/user",
        env={**os.environ, "GOMAXPROCS": "4"},
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=90,
    )
    assert result.returncode == 0, f"analyze.go failed when executed:\n{result.stdout}"
    assert os.path.exists(JSON_FILE), f"The file {JSON_FILE} does not exist after execution."
    assert os.path.isfile(JSON_FILE), f"{JSON_FILE} is not a file."

    try:
        with open(JSON_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        pytest.fail(f"Failed to parse {JSON_FILE} as JSON: {e}")

    required_keys = {"mean_com", "ci_lower", "ci_upper"}
    assert required_keys.issubset(data.keys()), f"{JSON_FILE} is missing keys: {required_keys - data.keys()}"
    for key in required_keys:
        value = data[key]
        assert isinstance(value, (int, float)) and not isinstance(value, bool), f"{key} must be a number"
        assert math.isfinite(value), f"{key} must be finite"
    assert data["ci_lower"] <= data["mean_com"] <= data["ci_upper"], "confidence interval must contain mean_com"
    return data


def write_synthetic_csv():
    # The out-of-range rows have huge intensities and must be ignored. For the
    # two included rows, a size-2 with-replacement bootstrap has CoMs 400, 475,
    # and 500 with probabilities 1/4, 1/2, and 1/4 respectively.
    with open(CSV_FILE, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["wavelength", "intensity"])
        writer.writerow([399.9, 1000000.0])
        writer.writerow([400.0, 1.0])
        writer.writerow([500.0, 3.0])
        writer.writerow([500.1, 1000000.0])


def reference_bootstrap(csv_path):
    wavelengths, intensities = [], []
    with open(csv_path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            wavelength = float(row["wavelength"])
            if 400.0 <= wavelength <= 500.0:
                wavelengths.append(wavelength)
                intensities.append(float(row["intensity"]))

    x = np.asarray(wavelengths, dtype=np.float64)
    y = np.asarray(intensities, dtype=np.float64)
    assert len(x) > 0
    rng = np.random.default_rng(8675309)
    estimates = np.empty(10000, dtype=np.float64)
    offset = 0
    while offset < 10000:
        count = min(250, 10000 - offset)
        indices = rng.integers(0, len(x), size=(count, len(x)))
        sampled_y = y[indices]
        estimates[offset:offset + count] = (
            (x[indices] * sampled_y).sum(axis=1) / sampled_y.sum(axis=1)
        )
        offset += count
    estimates.sort()
    return {
        "mean_com": float(estimates.mean()),
        "ci_lower": float(estimates[250]),
        "ci_upper": float(estimates[9750]),
    }


def test_program_executes_and_computes_bootstrap(compiled_binary, tmp_path):
    original = tmp_path / "spectra.csv"
    shutil.copy2(CSV_FILE, original)
    try:
        write_synthetic_csv()
        synthetic = run_submission(compiled_binary)
        assert math.isclose(synthetic["ci_lower"], 400.0, abs_tol=1e-9), synthetic
        assert math.isclose(synthetic["ci_upper"], 500.0, abs_tol=1e-9), synthetic
        assert abs(synthetic["mean_com"] - 462.5) <= 2.0, synthetic

        shutil.copy2(original, CSV_FILE)
        expected = reference_bootstrap(CSV_FILE)
        actual = run_submission(compiled_binary)
        assert abs(actual["mean_com"] - expected["mean_com"]) <= 0.08, (actual, expected)
        assert abs(actual["ci_lower"] - expected["ci_lower"]) <= 0.12, (actual, expected)
        assert abs(actual["ci_upper"] - expected["ci_upper"]) <= 0.12, (actual, expected)
    finally:
        shutil.copy2(original, CSV_FILE)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
