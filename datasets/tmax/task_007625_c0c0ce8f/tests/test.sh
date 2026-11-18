#!/bin/bash
mkdir -p /logs/verifier

cat <<'GO_EOF' > /tmp/check_pipeline_ast.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "strconv"
)

func importAlias(f *ast.File, wanted string) (string, bool) {
    for _, imp := range f.Imports {
        p, err := strconv.Unquote(imp.Path.Value)
        if err != nil || p != wanted {
            continue
        }
        if imp.Name != nil {
            return imp.Name.Name, true
        }
        if wanted == "time" {
            return "time", true
        }
        return "mat", true
    }
    return "", false
}

func selectorCall(expr ast.Expr, alias, name string) bool {
    call, ok := expr.(*ast.CallExpr)
    if !ok {
        return false
    }
    if alias == "." {
        id, ok := call.Fun.(*ast.Ident)
        return ok && id.Name == name
    }
    sel, ok := call.Fun.(*ast.SelectorExpr)
    if !ok || sel.Sel.Name != name {
        return false
    }
    id, ok := sel.X.(*ast.Ident)
    return ok && id.Name == alias
}

func startAssignment(stmt ast.Stmt, timeAlias string) (string, bool) {
    as, ok := stmt.(*ast.AssignStmt)
    if !ok || len(as.Lhs) != 1 || len(as.Rhs) != 1 || !selectorCall(as.Rhs[0], timeAlias, "Now") {
        return "", false
    }
    id, ok := as.Lhs[0].(*ast.Ident)
    return id.Name, ok
}

func containsMul(stmt ast.Stmt) bool {
    found := false
    ast.Inspect(stmt, func(n ast.Node) bool {
        call, ok := n.(*ast.CallExpr)
        if !ok {
            return true
        }
        sel, ok := call.Fun.(*ast.SelectorExpr)
        if ok && sel.Sel.Name == "Mul" && len(call.Args) == 2 {
            found = true
        }
        return true
    })
    return found
}

func containsElapsedFor(stmt ast.Stmt, timeAlias, start string) bool {
    hasSince := false
    hasNanoseconds := false
    ast.Inspect(stmt, func(n ast.Node) bool {
        call, ok := n.(*ast.CallExpr)
        if !ok {
            return true
        }
        if selectorCall(call, timeAlias, "Since") && len(call.Args) == 1 {
            if id, ok := call.Args[0].(*ast.Ident); ok && id.Name == start {
                hasSince = true
            }
        }
        if sel, ok := call.Fun.(*ast.SelectorExpr); ok && sel.Sel.Name == "Nanoseconds" {
            hasNanoseconds = true
        }
        return true
    })
    return hasSince && hasNanoseconds
}

func main() {
    path := os.Args[len(os.Args)-1]
    f, err := parser.ParseFile(token.NewFileSet(), path, nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    matAlias, hasMat := importAlias(f, "gonum.org/v1/gonum/mat")
    timeAlias, hasTime := importAlias(f, "time")
    if !hasMat || !hasTime {
        fmt.Fprintln(os.Stderr, "pipeline.go must import gonum.org/v1/gonum/mat and time")
        os.Exit(1)
    }

    usesMat := false
    hasTimedMul := false
    ast.Inspect(f, func(n ast.Node) bool {
        if call, ok := n.(*ast.CallExpr); ok {
            if sel, ok := call.Fun.(*ast.SelectorExpr); ok && sel.Sel.Name == "Mul" {
                usesMat = true
            }
            if matAlias == "." {
                if id, ok := call.Fun.(*ast.Ident); ok && (id.Name == "NewDense" || id.Name == "NewVecDense") {
                    usesMat = true
                }
            } else if sel, ok := call.Fun.(*ast.SelectorExpr); ok {
                if id, ok := sel.X.(*ast.Ident); ok && id.Name == matAlias {
                    usesMat = true
                }
            }
        }

        block, ok := n.(*ast.BlockStmt)
        if !ok {
            return true
        }
        for i := 0; i+2 < len(block.List); i++ {
            start, ok := startAssignment(block.List[i], timeAlias)
            if ok && containsMul(block.List[i+1]) && containsElapsedFor(block.List[i+2], timeAlias, start) {
                hasTimedMul = true
            }
        }
        return true
    })

    if !usesMat {
        fmt.Fprintln(os.Stderr, "pipeline.go does not use the imported Gonum matrix package")
        os.Exit(1)
    }
    if !hasTimedMul {
        fmt.Fprintln(os.Stderr, "matrix Mul must be directly bracketed by time.Now() and time.Since(...).Nanoseconds()")
        os.Exit(1)
    }
}
GO_EOF

cat <<'PY_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import pytest


def test_go_module_initialized():
    go_mod_path = "/home/user/mlops/go.mod"
    assert os.path.exists(go_mod_path), f"Expected Go module to be initialized at {go_mod_path}"
    text = open(go_mod_path, encoding="utf-8").read()
    assert re.search(r"(?m)^module\s+mlops\s*$", text), "Go module must be named mlops"


def test_pipeline_go_exists():
    pipeline_path = "/home/user/mlops/pipeline.go"
    assert os.path.exists(pipeline_path), f"Expected Go program to exist at {pipeline_path}"
    assert os.path.isfile(pipeline_path), f"Expected {pipeline_path} to be a regular file"


def test_benchmark_json():
    benchmark_path = "/home/user/mlops/benchmark.json"
    assert os.path.exists(benchmark_path), f"Benchmark JSON not found at {benchmark_path}"
    with open(benchmark_path, encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("benchmark.json is not valid JSON")

    assert "lines_processed" in data, "lines_processed missing in benchmark.json"
    assert "duration_ns" in data, "duration_ns missing in benchmark.json"
    assert set(data) == {"lines_processed", "duration_ns"}, "benchmark.json has unexpected fields"

    with open("/home/user/corpus.txt", encoding="utf-8") as f:
        expected_lines = len(f.readlines())
    assert data["lines_processed"] == expected_lines, f"Expected {expected_lines} lines processed, got {data['lines_processed']}"
    assert type(data["lines_processed"]) is int, "lines_processed must be an integer"
    assert type(data["duration_ns"]) is int, "duration_ns must be an integer"
    assert data["duration_ns"] > 0, "duration_ns must be positive"


def test_reduced_csv():
    artifacts_path = "/home/user/mlops/artifacts/reduced.csv"
    assert os.path.exists(artifacts_path), f"Artifacts CSV not found at {artifacts_path}"

    with open("/home/user/corpus.txt", encoding="utf-8") as f:
        lines = f.readlines()

    X = []
    for line in lines:
        counts = [0] * 26
        for char in line.lower():
            if "a" <= char <= "z":
                counts[ord(char) - ord("a")] += 1
        X.append(counts)

    P = []
    with open("/home/user/projection.csv", newline="", encoding="utf-8") as f:
        for row in csv.reader(f):
            P.append([float(x) for x in row])
    assert len(P) == 26 and all(len(row) == 5 for row in P)

    expected_Y = [
        [sum(X[i][k] * P[k][j] for k in range(26)) for j in range(5)]
        for i in range(len(X))
    ]

    actual_Y = []
    with open(artifacts_path, newline="", encoding="utf-8") as f:
        for row in csv.reader(f):
            if row:
                assert all(re.fullmatch(r"-?\d+\.\d{4}", x) for x in row), "Every value must have exactly four decimal places"
                try:
                    actual_Y.append([float(x) for x in row])
                except ValueError:
                    pytest.fail("reduced.csv contains non-float values")

    assert len(actual_Y) == len(expected_Y), f"Expected {len(expected_Y)} rows in reduced.csv, got {len(actual_Y)}"
    for i in range(len(expected_Y)):
        assert len(actual_Y[i]) == 5, f"Expected 5 columns at row {i}, got {len(actual_Y[i])}"
        for j in range(5):
            exp = expected_Y[i][j]
            act = actual_Y[i][j]
            assert math.isclose(exp, act, abs_tol=1e-3), f"Mismatch at row {i} col {j}: expected {exp}, got {act}"
PY_EOF

run_pipeline_and_tests() {
    rm -f /home/user/mlops/benchmark.json /home/user/mlops/artifacts/reduced.csv
    (cd /home/user/mlops && timeout 120s go run ./pipeline.go) || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1
}

verify_all() {
    test -f /home/user/mlops/go.mod || return 1
    test -f /home/user/mlops/pipeline.go || return 1
    grep -Eq '^module[[:space:]]+mlops[[:space:]]*$' /home/user/mlops/go.mod || return 1
    grep -q 'gonum.org/v1/gonum' /home/user/mlops/go.mod || return 1
    go run /tmp/check_pipeline_ast.go -- /home/user/mlops/pipeline.go || return 1

    # Execute and validate against the supplied inputs first.
    run_pipeline_and_tests || return 1

    # Preserve the valid supplied-input state while exercising fresh, unpredictable inputs.
    backup=$(mktemp -d)
    cp /home/user/corpus.txt "$backup/corpus.txt"
    cp /home/user/projection.csv "$backup/projection.csv"
    cp /home/user/mlops/benchmark.json "$backup/benchmark.json"
    cp /home/user/mlops/artifacts/reduced.csv "$backup/reduced.csv"

    python3 - <<'PY'
import random
import secrets
import string
r = random.SystemRandom()
with open('/home/user/corpus.txt', 'w', encoding='utf-8') as f:
    for _ in range(r.randint(3, 9)):
        chars = string.ascii_letters + string.digits + ' !?,-_é'
        f.write(''.join(r.choice(chars) for _ in range(r.randint(8, 90))) + '\n')
with open('/home/user/projection.csv', 'w', encoding='utf-8') as f:
    for _ in range(26):
        f.write(','.join(f'{r.uniform(-3.0, 3.0):.9f}' for _ in range(5)) + '\n')
PY

    run_pipeline_and_tests
    dynamic_status=$?

    cp "$backup/corpus.txt" /home/user/corpus.txt
    cp "$backup/projection.csv" /home/user/projection.csv
    mkdir -p /home/user/mlops/artifacts
    cp "$backup/benchmark.json" /home/user/mlops/benchmark.json
    cp "$backup/reduced.csv" /home/user/mlops/artifacts/reduced.csv
    rm -rf "$backup"

    return $dynamic_status
}

if verify_all 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
