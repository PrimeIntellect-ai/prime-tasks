#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/check_structure.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "strings"
)

func astLike(name string) bool {
    n := strings.ToLower(name)
    for _, part := range []string{"ast", "node", "expr", "tree", "binary", "literal", "number"} {
        if strings.Contains(n, part) {
            return true
        }
    }
    return false
}

func main() {
    if len(os.Args) != 2 {
        os.Exit(2)
    }
    fset := token.NewFileSet()
    packages, err := parser.ParseDir(fset, os.Args[1], func(info os.FileInfo) bool {
        return strings.HasSuffix(info.Name(), ".go") && !strings.HasSuffix(info.Name(), "_test.go")
    }, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    hasGo, hasChannel, hasChannelIO := false, false, false
    candidates := map[string]int{}

    for _, pkg := range packages {
        for _, file := range pkg.Files {
            ast.Inspect(file, func(n ast.Node) bool {
                switch x := n.(type) {
                case *ast.GoStmt:
                    hasGo = true
                case *ast.ChanType:
                    hasChannel = true
                case *ast.SendStmt:
                    hasChannelIO = true
                case *ast.UnaryExpr:
                    if x.Op == token.ARROW {
                        hasChannelIO = true
                    }
                case *ast.TypeSpec:
                    if astLike(x.Name.Name) {
                        switch x.Type.(type) {
                        case *ast.StructType, *ast.InterfaceType:
                            candidates[x.Name.Name] = 0
                        }
                    }
                }
                return true
            })
        }
    }

    for _, pkg := range packages {
        for _, file := range pkg.Files {
            ast.Inspect(file, func(n ast.Node) bool {
                if id, ok := n.(*ast.Ident); ok {
                    if _, exists := candidates[id.Name]; exists {
                        candidates[id.Name]++
                    }
                }
                return true
            })
        }
    }

    usedCustomAST := false
    for _, uses := range candidates {
        if uses > 1 {
            usedCustomAST = true
        }
    }

    if !hasGo || !hasChannel || !hasChannelIO {
        fmt.Fprintln(os.Stderr, "main implementation must contain goroutines and a channel used for communication")
        os.Exit(1)
    }
    if !usedCustomAST {
        fmt.Fprintln(os.Stderr, "no used custom AST data type was found")
        os.Exit(1)
    }
}
GO_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import time

PROJECT = "/home/user/aud-eval"
BIN = os.path.join(PROJECT, "bin/aud-eval")
MODULUS = 733


def trunc_div(a, b):
    assert b != 0
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def generate_test_data(num_equations=200000):
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    equations = []
    reference = []
    ops = ["+", "-", "*", "/"]

    def combine(a, b, op):
        if op == "+":
            return a + b
        if op == "-":
            return a - b
        if op == "*":
            return a * b
        return trunc_div(a, b)

    def make_expr(depth, forced_op=None):
        if depth == 0:
            value = rng.randint(1, 9)
            return str(value), value

        op = forced_op if forced_op is not None else rng.choice(ops)
        left, left_value = make_expr(depth - 1)
        for _ in range(100):
            right, right_value = make_expr(depth - 1)
            if op != "/" or right_value != 0:
                break
        else:
            right, right_value = "1", 1

        spaces = ["", " ", "  "]
        before = rng.choice(spaces)
        after = rng.choice(spaces)
        expression = "(" + left + before + op + after + right + ")"
        return expression, combine(left_value, right_value, op)

    for i in range(num_equations):
        # Thousands of genuinely recursive, varied trees exercise arbitrary nesting.
        # The remainder retains the original test's scale without making every line large.
        depth = 4 if i < 2000 else rng.choice((1, 2, 2))
        forced = ops[i % len(ops)] if i < 2000 else None
        expr, value = make_expr(depth, forced)
        if rng.random() < 0.35:
            expr = expr[1:-1]  # Also exercise an unwrapped top-level expression.

        checksum = sum(ord(ch) for ch in expr.replace(" ", ""))
        if rng.random() < 0.05:
            checksum += rng.choice((-2, -1, 1, 2))
        else:
            reference.append(f"{expr},{value % MODULUS}")
        equations.append(f"{expr} | {checksum}")

    return equations, reference


def rebuild_submission():
    subprocess.run(
        ["go", "run", "/tmp/check_structure.go", PROJECT],
        check=True,
        timeout=30,
    )

    os.makedirs(os.path.dirname(BIN), exist_ok=True)
    command = ["go", "build", "-o", BIN, "."]
    first = subprocess.run(command, cwd=PROJECT, capture_output=True, text=True)
    if first.returncode != 0:
        env = os.environ.copy()
        env["GO111MODULE"] = "off"
        second = subprocess.run(command, cwd=PROJECT, env=env, capture_output=True, text=True)
        assert second.returncode == 0, first.stderr + "\n" + second.stderr


def test_aud_eval_accuracy_and_speed():
    assert os.path.isfile(BIN), f"Compiled binary not found at {BIN}"
    rebuild_submission()
    assert os.path.isfile(BIN), f"Compiled binary not found at {BIN}"

    equations, reference = generate_test_data(200000)
    test_file = os.path.join(PROJECT, "test_equations.txt")
    target_file = os.path.join(PROJECT, "equations.txt")
    payload = "\n".join(equations) + "\n"
    with open(test_file, "w") as f:
        f.write(payload)
    with open(target_file, "w") as f:
        f.write(payload)

    results_file = os.path.join(PROJECT, "results.csv")
    if os.path.exists(results_file):
        os.remove(results_file)

    start_time = time.time()
    try:
        subprocess.run([BIN, target_file], check=True, cwd=PROJECT, timeout=10)
    except subprocess.CalledProcessError:
        subprocess.run([BIN], check=True, cwd=PROJECT, timeout=10)
    duration = time.time() - start_time

    assert os.path.isfile(results_file), f"Results file not found at {results_file}"
    with open(results_file, "r") as f:
        agent_lines = f.read().splitlines()

    correct = sum(1 for actual, expected in zip(agent_lines, reference) if actual == expected)
    accuracy = correct / max(len(reference), 1)
    assert accuracy >= 1.0, f"Accuracy too low: {accuracy} (Expected 1.0)"
    assert agent_lines == reference, "Results contain missing, extra, reordered, or incorrect lines"
    assert duration <= 1.5, f"Execution too slow: {duration}s (Expected <= 1.5s)"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
