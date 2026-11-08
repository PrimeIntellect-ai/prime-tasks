#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/inspect_submission.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "path/filepath"
    "strconv"
    "strings"
)

func main() {
    appDir := os.Args[1]
    fset := token.NewFileSet()
    hasGoStmt := false
    hasGonumUse := false

    entries, err := os.ReadDir(appDir)
    if err != nil { panic(err) }
    for _, entry := range entries {
        if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".go") || strings.HasSuffix(entry.Name(), "_test.go") {
            continue
        }
        f, err := parser.ParseFile(fset, filepath.Join(appDir, entry.Name()), nil, 0)
        if err != nil { panic(err) }
        aliases := map[string]bool{}
        for _, imp := range f.Imports {
            path, _ := strconv.Unquote(imp.Path.Value)
            if path == "gonum.org/v1/gonum/mat" {
                alias := "mat"
                if imp.Name != nil { alias = imp.Name.Name }
                if alias != "_" && alias != "." { aliases[alias] = true }
            }
        }
        ast.Inspect(f, func(n ast.Node) bool {
            switch x := n.(type) {
            case *ast.GoStmt:
                hasGoStmt = true
            case *ast.SelectorExpr:
                if id, ok := x.X.(*ast.Ident); ok && aliases[id.Name] {
                    hasGonumUse = true
                }
            }
            return true
        })
    }

    meaningfulRegression := false
    testPath := filepath.Join(appDir, "main_test.go")
    tf, err := parser.ParseFile(fset, testPath, nil, 0)
    if err != nil { panic(err) }
    for _, decl := range tf.Decls {
        fn, ok := decl.(*ast.FuncDecl)
        if !ok || fn.Body == nil || !strings.HasPrefix(fn.Name.Name, "Test") { continue }
        hasSequence, hasKmer, hasOne, hasIf, hasFailure := false, false, false, false, false
        ast.Inspect(fn.Body, func(n ast.Node) bool {
            switch x := n.(type) {
            case *ast.BasicLit:
                if x.Kind == token.STRING {
                    value, _ := strconv.Unquote(x.Value)
                    if value == "ACGTG" { hasSequence = true }
                    if value == "CG" { hasKmer = true }
                }
                if x.Kind == token.INT && x.Value == "1" { hasOne = true }
            case *ast.IfStmt:
                hasIf = true
            case *ast.CallExpr:
                if sel, ok := x.Fun.(*ast.SelectorExpr); ok {
                    switch sel.Sel.Name {
                    case "Error", "Errorf", "Fatal", "Fatalf", "Fail", "FailNow":
                        hasFailure = true
                    }
                }
            }
            return true
        })
        if hasSequence && hasKmer && hasOne && hasIf && hasFailure {
            meaningfulRegression = true
        }
    }

    fmt.Printf("%t %t %t\n", hasGoStmt, hasGonumUse, meaningfulRegression)
}
GO_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess

APP_DIR = "/home/user/kmer_app"
FASTA = "/home/user/sequences.fasta"
TRACE = "/home/user/trace.txt"


def test_trace_txt_exists_and_correct():
    """Verify that trace.txt exists and contains the correct trace value."""
    assert os.path.exists(TRACE), f"File {TRACE} does not exist."
    with open(TRACE, "r") as f:
        content = f.read().strip()
    assert content == "126.9821", f"Expected trace value '126.9821', but got '{content}'."


def test_fasta_file_exists():
    """Verify that sequences.fasta exists with correct content."""
    assert os.path.exists(FASTA), f"File {FASTA} does not exist."
    with open(FASTA, "r") as f:
        content = f.read()
    expected_sequences = ["AAAAA", "ACGTG", "AAAAAC", "TTTTT"]
    for seq in expected_sequences:
        assert seq in content, f"Expected sequence '{seq}' not found in {FASTA}."
    assert content == ">seq1\nAAAAA\n>seq2\nACGTG\n>seq3\nAAAAAC\n>seq4\nTTTTT\n"


def test_go_app_files_exist():
    """Verify that main.go and main_test.go exist."""
    for path in [f"{APP_DIR}/main.go", f"{APP_DIR}/main_test.go", f"{APP_DIR}/go.mod"]:
        assert os.path.exists(path), f"File {path} does not exist."


def test_go_test_file_content():
    """Verify that main_test.go contains tests for 'ACGTG' and 'CG'."""
    with open(f"{APP_DIR}/main_test.go", "r") as f:
        content = f.read()
    assert "ACGTG" in content, "main_test.go does not contain the test sequence 'ACGTG'."
    assert "CG" in content, "main_test.go does not check for the 'CG' 2-mer."


def test_go_tests_pass():
    """Verify that go test passes in the kmer_app directory."""
    assert os.path.isdir(APP_DIR), f"Directory {APP_DIR} does not exist."
    result = subprocess.run(["go", "test"], cwd=APP_DIR, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=120)
    assert result.returncode == 0, f"'go test' failed in {APP_DIR}:\n{result.stderr}\n{result.stdout}"


def inverse_trace(sequences):
    kmers = [a + b for a in "ACGT" for b in "ACGT"]
    index = {k: i for i, k in enumerate(kmers)}
    x = []
    for seq in sequences:
        row = [0.0] * 16
        for i in range(len(seq) - 1):
            row[index[seq[i:i+2]]] += 1.0
        x.append(row)
    c = [[0.0] * 16 for _ in range(16)]
    for i in range(16):
        for j in range(16):
            c[i][j] = sum(row[i] * row[j] for row in x)
        c[i][i] += 0.1
    aug = [c[i][:] + [1.0 if i == j else 0.0 for j in range(16)] for i in range(16)]
    for col in range(16):
        pivot = max(range(col, 16), key=lambda r: abs(aug[r][col]))
        aug[col], aug[pivot] = aug[pivot], aug[col]
        scale = aug[col][col]
        assert abs(scale) > 1e-12
        aug[col] = [v / scale for v in aug[col]]
        for r in range(16):
            if r != col:
                factor = aug[r][col]
                aug[r] = [aug[r][j] - factor * aug[col][j] for j in range(32)]
    return sum(aug[i][16 + i] for i in range(16))


def run_case(sequences):
    with open(FASTA, "w") as f:
        for i, seq in enumerate(sequences, 1):
            f.write(f">case{i}\n{seq}\n")
    if os.path.exists(TRACE):
        os.remove(TRACE)
    result = subprocess.run(["go", "run", "."], cwd=APP_DIR, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=120)
    assert result.returncode == 0, f"go run failed:\n{result.stderr}\n{result.stdout}"
    assert os.path.isfile(TRACE), "Running the Go program did not create trace.txt"
    raw = open(TRACE).read()
    assert re.fullmatch(r"[0-9]+\.[0-9]{4}\n?", raw), f"Trace is not formatted to exactly four decimals: {raw!r}"
    expected = f"{inverse_trace(sequences):.4f}"
    assert raw.strip() == expected, f"For {sequences}, expected {expected}, got {raw.strip()}"


def test_implementation_and_dynamic_execution():
    module = subprocess.run(["go", "list", "-m"], cwd=APP_DIR, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    assert module.returncode == 0 and module.stdout.strip() == "kmer_extractor"

    inspection = subprocess.run(["go", "run", "/tmp/inspect_submission.go", APP_DIR],
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    assert inspection.returncode == 0, inspection.stderr
    assert inspection.stdout.strip() == "true true true", (
        "The implementation must contain a goroutine, actually use gonum/mat, and main_test.go "
        "must contain a failing assertion for ACGTG/CG against 1."
    )

    original_fasta = open(FASTA, "rb").read()
    original_trace = open(TRACE, "rb").read() if os.path.exists(TRACE) else None
    rng = random.SystemRandom()
    random_case = ["".join(rng.choice("ACGT") for _ in range(rng.randrange(3, 11)))
                   for _ in range(rng.randrange(4, 8))]
    try:
        run_case(["ACGTG", "CGCG", "TATA", "GGAACC"])
        run_case(random_case)
    finally:
        open(FASTA, "wb").write(original_fasta)
        if original_trace is None:
            if os.path.exists(TRACE): os.remove(TRACE)
        else:
            open(TRACE, "wb").write(original_trace)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
