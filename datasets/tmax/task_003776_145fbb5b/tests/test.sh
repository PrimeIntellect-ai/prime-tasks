#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/check_mc_ast.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "strconv"
    "strings"
)

func isFour(e ast.Expr, fourNames map[string]bool) bool {
    switch x := e.(type) {
    case *ast.BasicLit:
        if x.Kind == token.INT {
            v, err := strconv.ParseInt(x.Value, 0, 64)
            return err == nil && v == 4
        }
    case *ast.Ident:
        return fourNames[x.Name]
    case *ast.ParenExpr:
        return isFour(x.X, fourNames)
    }
    return false
}

func containsGo(n ast.Node) bool {
    found := false
    ast.Inspect(n, func(x ast.Node) bool {
        if _, ok := x.(*ast.GoStmt); ok {
            found = true
        }
        return !found
    })
    return found
}

func main() {
    if len(os.Args) != 2 {
        os.Exit(2)
    }
    fset := token.NewFileSet()
    f, err := parser.ParseFile(fset, os.Args[1], nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    randNames := map[string]bool{}
    for _, imp := range f.Imports {
        if strings.Trim(imp.Path.Value, "\"") == "math/rand" {
            name := "rand"
            if imp.Name != nil {
                name = imp.Name.Name
            }
            randNames[name] = true
        }
    }
    if len(randNames) == 0 {
        fmt.Fprintln(os.Stderr, "math/rand is not imported")
        os.Exit(1)
    }

    fourNames := map[string]bool{}
    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.ValueSpec:
            for i, name := range x.Names {
                if i < len(x.Values) && isFour(x.Values[i], fourNames) {
                    fourNames[name.Name] = true
                }
            }
        case *ast.AssignStmt:
            for i, lhs := range x.Lhs {
                if i < len(x.Rhs) && isFour(x.Rhs[i], fourNames) {
                    if id, ok := lhs.(*ast.Ident); ok {
                        fourNames[id.Name] = true
                    }
                }
            }
        }
        return true
    })

    goCount := 0
    hasFourWorkers := false
    hasRandNew := false
    hasRandNewSource := false
    floatCalls := 0
    hasComparison := false

    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.GoStmt:
            goCount++
        case *ast.ForStmt:
            if containsGo(x.Body) && x.Cond != nil {
                ast.Inspect(x.Cond, func(c ast.Node) bool {
                    if e, ok := c.(ast.Expr); ok && isFour(e, fourNames) {
                        hasFourWorkers = true
                    }
                    return true
                })
            }
        case *ast.CallExpr:
            switch fun := x.Fun.(type) {
            case *ast.SelectorExpr:
                if id, ok := fun.X.(*ast.Ident); ok && randNames[id.Name] {
                    if fun.Sel.Name == "New" {
                        hasRandNew = true
                    }
                    if fun.Sel.Name == "NewSource" {
                        hasRandNewSource = true
                    }
                }
                if fun.Sel.Name == "Float64" {
                    floatCalls++
                }
            case *ast.Ident:
                if randNames["."] {
                    if fun.Name == "New" {
                        hasRandNew = true
                    }
                    if fun.Name == "NewSource" {
                        hasRandNewSource = true
                    }
                    if fun.Name == "Float64" {
                        floatCalls++
                    }
                }
            }
        case *ast.BinaryExpr:
            switch x.Op {
            case token.LSS, token.LEQ, token.GTR, token.GEQ:
                hasComparison = true
            }
        }
        return true
    })

    if goCount >= 4 {
        hasFourWorkers = true
    }
    if goCount == 0 || !hasFourWorkers {
        fmt.Fprintln(os.Stderr, "could not verify that exactly four worker goroutines are launched")
        os.Exit(1)
    }
    if !hasRandNew || !hasRandNewSource {
        fmt.Fprintln(os.Stderr, "workers do not use independently constructed local math/rand generators")
        os.Exit(1)
    }
    if floatCalls < 2 || !hasComparison {
        fmt.Fprintln(os.Stderr, "could not find the random candidate/acceptance comparison required for rejection sampling")
        os.Exit(1)
    }
}
GO_EOF

go build -o /tmp/check_mc_ast /tmp/check_mc_ast.go

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import subprocess

GO_FILE = '/home/user/mc_sampler.go'
LOG_FILE = '/home/user/convergence.log'


def validate_log(path):
    assert os.path.exists(path), f"{path} does not exist."

    with open(path, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {path}, got {len(lines)}."

    try:
        n1, v1_str = lines[0].split(',')
        n2, v2_str = lines[1].split(',')
        n3, v3_str = lines[2].split(',')
    except ValueError:
        raise AssertionError("Lines in convergence.log must be formatted as 'N,value'.")

    assert n1 == "10000", f"Expected first N to be 10000, got {n1}"
    assert n2 == "100000", f"Expected second N to be 100000, got {n2}"
    assert n3 == "1000000", f"Expected third N to be 1000000, got {n3}"

    try:
        v1 = float(v1_str)
        v2 = float(v2_str)
        v3 = float(v3_str)
    except ValueError:
        raise AssertionError("The distance values in convergence.log must be valid floats.")

    assert all(math.isfinite(v) for v in (v1, v2, v3)), "KS distances must be finite."
    assert 0.001 < v1 < 0.05, f"Value for N=10000 ({v1}) is out of expected stochastic bounds (0.001 to 0.05)."
    assert 0.0001 < v2 < 0.015, f"Value for N=100000 ({v2}) is out of expected stochastic bounds (0.0001 to 0.015)."
    assert 0.00001 < v3 < 0.005, f"Value for N=1000000 ({v3}) is out of expected stochastic bounds (0.00001 to 0.005)."
    assert v1 > v3, f"Convergence failed: distance for N=10^4 ({v1}) is not greater than N=10^6 ({v3})."


def test_mc_sampler_go_exists_and_contains_concurrency():
    """Preserve the original source/concurrency assertions."""
    assert os.path.exists(GO_FILE), f"{GO_FILE} does not exist."
    with open(GO_FILE, 'r', encoding='utf-8') as f:
        content = f.read()

    assert "go " in content, "The Go program does not appear to use goroutines ('go ' keyword missing)."
    has_chan = "chan " in content
    has_wg = "WaitGroup" in content
    assert has_chan or has_wg, "The Go program does not appear to use channels or WaitGroup for synchronization."


def test_convergence_log_exists_and_format():
    """Preserve the original checks on the log the agent was instructed to generate."""
    validate_log(LOG_FILE)


def test_program_has_required_sampling_structure():
    """Use Go's parser rather than substring-only checks for the core implementation."""
    result = subprocess.run(
        ['/tmp/check_mc_ast', GO_FILE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, result.stderr or result.stdout


def test_program_compiles_executes_and_regenerates_log():
    """Delete the submitted log, compile the artifact, and validate a freshly generated result."""
    build = subprocess.run(
        ['go', 'build', '-o', '/tmp/mc_sampler_under_test', GO_FILE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"mc_sampler.go does not compile:\n{build.stderr}"

    if os.path.lexists(LOG_FILE):
        os.unlink(LOG_FILE)

    env = os.environ.copy()
    env['GOMAXPROCS'] = '4'
    run = subprocess.run(
        ['/tmp/mc_sampler_under_test'],
        cwd='/home/user',
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert run.returncode == 0, f"mc_sampler program failed:\n{run.stderr}"
    assert os.path.isfile(LOG_FILE), "The executed program did not create /home/user/convergence.log."
    validate_log(LOG_FILE)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
