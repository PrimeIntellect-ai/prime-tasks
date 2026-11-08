#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/check_simulation_ast.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)

func containsUnitShift(expr ast.Expr) bool {
    found := false
    ast.Inspect(expr, func(n ast.Node) bool {
        b, ok := n.(*ast.BinaryExpr)
        if !ok || (b.Op != token.ADD && b.Op != token.SUB) {
            return true
        }
        isOne := func(e ast.Expr) bool {
            lit, ok := e.(*ast.BasicLit)
            return ok && lit.Kind == token.INT && lit.Value == "1"
        }
        if isOne(b.X) || isOne(b.Y) {
            found = true
            return false
        }
        return true
    })
    return found
}

func main() {
    path := "/home/user/diffusion/simulate.go"
    fset := token.NewFileSet()
    file, err := parser.ParseFile(fset, path, nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    hasMain := false
    loops := 0
    depth, maxDepth := 0, 0
    indices := 0
    shiftedIndices := 0
    indexedWrites := 0
    ops := map[token.Token]bool{}
    stack := []bool{}

    ast.Inspect(file, func(n ast.Node) bool {
        if n == nil {
            if len(stack) > 0 {
                wasLoop := stack[len(stack)-1]
                stack = stack[:len(stack)-1]
                if wasLoop {
                    depth--
                }
            }
            return true
        }

        isLoop := false
        switch n.(type) {
        case *ast.ForStmt, *ast.RangeStmt:
            isLoop = true
            loops++
            depth++
            if depth > maxDepth {
                maxDepth = depth
            }
        }
        stack = append(stack, isLoop)

        switch v := n.(type) {
        case *ast.FuncDecl:
            if v.Name.Name == "main" && v.Recv == nil {
                hasMain = true
            }
        case *ast.IndexExpr:
            indices++
            if containsUnitShift(v.Index) {
                shiftedIndices++
            }
        case *ast.AssignStmt:
            for _, lhs := range v.Lhs {
                if _, ok := lhs.(*ast.IndexExpr); ok {
                    indexedWrites++
                }
            }
        case *ast.IncDecStmt:
            if _, ok := v.X.(*ast.IndexExpr); ok {
                indexedWrites++
            }
        case *ast.BinaryExpr:
            ops[v.Op] = true
        }
        return true
    })

    if file.Name.Name != "main" || !hasMain {
        fmt.Fprintln(os.Stderr, "simulate.go must define package main and a main function")
        os.Exit(1)
    }
    if loops < 4 || maxDepth < 3 {
        fmt.Fprintln(os.Stderr, "simulate.go does not contain the required time/grid iteration structure")
        os.Exit(1)
    }
    if indices < 10 || shiftedIndices < 4 || indexedWrites < 2 {
        fmt.Fprintln(os.Stderr, "simulate.go does not contain a finite-difference grid stencil")
        os.Exit(1)
    }
    if !ops[token.ADD] || !ops[token.SUB] || !ops[token.MUL] {
        fmt.Fprintln(os.Stderr, "simulate.go is missing arithmetic required by the heat-equation update")
        os.Exit(1)
    }
}
GO_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess

DIFFUSION_DIR = "/home/user/diffusion"
LOG_PATH = "/home/user/mse_validation.log"


def reference_mse():
    size = 50
    alpha = 1.0
    dt = 0.1
    grid = [[0.0 for _ in range(size)] for _ in range(size)]
    grid[25][25] = 1000.0

    for _ in range(100):
        nxt = [[0.0 for _ in range(size)] for _ in range(size)]
        for y in range(1, size - 1):
            for x in range(1, size - 1):
                laplacian = (
                    grid[y][x + 1] - 2.0 * grid[y][x] + grid[y][x - 1]
                    + grid[y + 1][x] - 2.0 * grid[y][x] + grid[y - 1][x]
                )
                nxt[y][x] = grid[y][x] + alpha * dt * laplacian
        grid = nxt

    total = 0.0
    for y in range(20, 30):
        for x in range(20, 30):
            exact = 1000.0 / (4.0 * math.pi * alpha * 10.0) * math.exp(
                -((x - 25.0) ** 2 + (y - 25.0) ** 2) / (4.0 * alpha * 10.0)
            )
            total += (grid[y][x] - exact) ** 2
    return total / 100.0


def test_go_module_and_simulate_exists():
    """Check that the Go module and simulate.go exist."""
    assert os.path.exists("/home/user/diffusion/go.mod"), "Go module was not initialized in /home/user/diffusion."
    assert os.path.exists("/home/user/diffusion/simulate.go"), "simulate.go was not found in /home/user/diffusion."
    assert os.path.isfile("/home/user/diffusion/go.mod")
    assert os.path.isfile("/home/user/diffusion/simulate.go")


def test_simulate_contains_finite_difference_implementation():
    result = subprocess.run(
        ["/usr/bin/go", "run", "/tmp/check_simulation_ast.go"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr or result.stdout


def test_run_program_and_generate_fresh_log():
    if os.path.lexists(LOG_PATH):
        assert not os.path.isdir(LOG_PATH), f"{LOG_PATH} is a directory"
        os.unlink(LOG_PATH)

    result = subprocess.run(
        ["/usr/bin/go", "run", "."],
        cwd=DIFFUSION_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, f"Go program failed:\n{result.stderr}\n{result.stdout}"
    assert os.path.isfile(LOG_PATH), "Running the Go program did not create the MSE log."


def test_mse_validation_log_exists_and_correct():
    """Check that the freshly generated log contains the independently calculated MSE."""
    assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} does not exist."

    with open(LOG_PATH, "r") as f:
        raw_content = f.read()
    content = raw_content.strip()

    # Preserve the original format/value assertion.
    match = re.search(r"MSE:\s*([0-9]+\.[0-9]+)", content)
    assert match is not None, f"Could not find 'MSE: <value>' in {LOG_PATH}. Content was: {content}"
    mse_value = float(match.group(1))
    expected_mse = 0.015926
    tolerance = 0.000010
    assert abs(mse_value - expected_mse) <= tolerance, \
        f"Calculated MSE {mse_value} is not within {tolerance} of expected {expected_mse}."

    # Enforce exactly one correctly formatted line and derive its answer independently.
    exact_match = re.fullmatch(r"MSE: ([0-9]+\.[0-9]{6})\n?", raw_content)
    assert exact_match is not None, "Log must contain exactly one line formatted as 'MSE: <value>' with 6 decimals."
    derived = reference_mse()
    assert f"{derived:.6f}" == f"{expected_mse:.6f}", "Verifier reference calculation is inconsistent."
    assert exact_match.group(1) == f"{derived:.6f}", \
        f"Log reported {exact_match.group(1)}, but independent simulation gives {derived:.6f}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
