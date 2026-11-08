#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'AST_EOF' > /tmp/check_simulator_ast.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)

func fail(message string) {
    fmt.Fprintln(os.Stderr, message)
    os.Exit(1)
}

func main() {
    if len(os.Args) != 2 {
        fail("expected simulator.go path")
    }

    file, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil {
        fail("could not parse simulator.go: " + err.Error())
    }

    var getSeed, mainFunc *ast.FuncDecl
    for _, decl := range file.Decls {
        fn, ok := decl.(*ast.FuncDecl)
        if !ok {
            continue
        }
        switch fn.Name.Name {
        case "getSeed":
            getSeed = fn
        case "main":
            mainFunc = fn
        }
    }

    if getSeed == nil || getSeed.Body == nil {
        fail("getSeed must have an implementation")
    }
    if getSeed.Type.Params != nil && len(getSeed.Type.Params.List) != 0 {
        fail("getSeed must not take arguments")
    }
    if getSeed.Type.Results == nil || len(getSeed.Type.Results.List) != 1 {
        fail("getSeed must return exactly one value")
    }
    resultType, ok := getSeed.Type.Results.List[0].Type.(*ast.Ident)
    if !ok || resultType.Name != "float64" {
        fail("getSeed must return float64")
    }
    if mainFunc == nil || mainFunc.Body == nil {
        fail("main must have an implementation")
    }

    callsGetSeed := false
    ast.Inspect(mainFunc.Body, func(node ast.Node) bool {
        call, ok := node.(*ast.CallExpr)
        if !ok {
            return true
        }
        ident, ok := call.Fun.(*ast.Ident)
        if ok && ident.Name == "getSeed" {
            callsGetSeed = true
        }
        return true
    })
    if !callsGetSeed {
        fail("main must use getSeed")
    }
}
AST_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import tempfile
import pytest


def expected_value():
    x = 0.54321
    r = 3.95
    for _ in range(10000):
        x = r * x * (1.0 - x)
    return f"{x:.6f}"


def test_simulator_builds_and_runs():
    source_path = "/home/user/simulator.go"
    assert os.path.exists(source_path), f"Missing source code at {source_path}"
    assert os.path.isfile(source_path), f"{source_path} is not a file"

    with tempfile.TemporaryDirectory() as temp_dir:
        ast_checker = os.path.join(temp_dir, "check_simulator_ast")
        checker_build = subprocess.run(
            ["go", "build", "-o", ast_checker, "/tmp/check_simulator_ast.go"],
            text=True,
            capture_output=True,
            timeout=30,
        )
        assert checker_build.returncode == 0, checker_build.stderr

        ast_check = subprocess.run(
            [ast_checker, source_path],
            text=True,
            capture_output=True,
            timeout=10,
        )
        assert ast_check.returncode == 0, ast_check.stderr

        simulator = os.path.join(temp_dir, "simulator")
        build = subprocess.run(
            ["go", "build", "-o", simulator, source_path],
            cwd="/home/user",
            text=True,
            capture_output=True,
            timeout=30,
        )
        assert build.returncode == 0, f"simulator.go does not build:\n{build.stderr}"
        assert os.path.isfile(simulator), "Go build did not produce a simulator executable"

        run = subprocess.run(
            [simulator],
            cwd="/home/user",
            text=True,
            capture_output=True,
            timeout=10,
        )
        assert run.returncode == 0, f"Corrected simulator failed when run:\n{run.stderr}"
        expected = expected_value()
        assert run.stdout == expected + "\n", (
            f"Simulator output is incorrect. Expected {expected!r}, got {run.stdout!r}"
        )


def test_result_txt_content():
    result_path = "/home/user/result.txt"
    assert os.path.exists(result_path), f"Missing result file at {result_path}"
    assert os.path.isfile(result_path), f"{result_path} is not a file"

    # Compute expected value using Python's float (IEEE 754 double precision)
    x = 0.54321
    r = 3.95
    for _ in range(10000):
        x = r * x * (1.0 - x)
    expected_val = f"{x:.6f}"

    with open(result_path, 'r') as f:
        actual_val = f.read().strip()

    assert actual_val == expected_val, f"Incorrect output in {result_path}. Expected {expected_val}, got {actual_val}"


def test_simulator_go_fixed():
    source_path = "/home/user/simulator.go"
    assert os.path.exists(source_path), f"Missing source code at {source_path}"

    with open(source_path, 'r') as f:
        content = f.read()

    assert "float32" not in content, "simulator.go still contains 'float32', numerical instability not fully fixed."
    assert "float64" in content, "simulator.go does not use 'float64' for the simulation."
    assert "0.54321" in content or ".54321" in content, "simulator.go does not seem to contain the extracted seed value."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
