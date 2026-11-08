#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast as py_ast
import json
import os
import secrets
import shutil
import subprocess
from pathlib import Path

import pytest

RUN_SH = "/home/user/run.sh"
AGGREGATOR_GO = "/home/user/aggregator.go"
OUTPUT_FILE = "/home/user/master_dataset.jsonl"

EXPECTED_ORIGINAL = [
    {"id": "101", "measurement": "5.45", "timestamp": "2023-10-01T10:00:00Z"},
    {"id": "102", "measurement": "5.46", "timestamp": "2023-10-01T10:01:00Z"},
    {"id": "103", "measurement": "9.12", "timestamp": "2023-10-01T10:02:00Z"},
    {"id": "104", "measurement": "9.15", "timestamp": "2023-10-01T10:03:00Z"},
    {"id": "105", "measurement": "7.77", "timestamp": "2023-10-01T10:04:00Z"},
]


def read_output():
    assert os.path.isfile(OUTPUT_FILE), f"Missing output file at {OUTPUT_FILE}"
    with open(OUTPUT_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    parsed = []
    for i, line in enumerate(lines):
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} in {OUTPUT_FILE} is not valid JSON: {line}")
        assert isinstance(value, dict), f"Line {i+1} is not a JSON object"
        parsed.append(value)
    return parsed


def assert_objects_equal(actual, expected):
    assert len(actual) == len(expected), \
        f"Expected {len(expected)} JSON objects, but found {len(actual)} in {OUTPUT_FILE}"
    actual_sorted = sorted(actual, key=lambda x: x.get("id", ""))
    expected_sorted = sorted(expected, key=lambda x: x["id"])
    assert actual_sorted == expected_sorted, \
        f"Output data does not match expected output. Expected: {expected_sorted}, Got: {actual_sorted}"


def execute_pipeline():
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    result = subprocess.run(
        [RUN_SH], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, \
        f"run.sh failed with exit code {result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"


def test_scripts_exist():
    assert os.path.isfile(RUN_SH), f"Missing shell script at {RUN_SH}"
    assert os.access(RUN_SH, os.X_OK), f"Shell script at {RUN_SH} is not executable"
    assert os.path.isfile(AGGREGATOR_GO), f"Missing Go program at {AGGREGATOR_GO}"


def test_go_program_uses_flock():
    with open(AGGREGATOR_GO, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "syscall.Flock" in content, "Go program is missing syscall.Flock"
    assert "syscall.LOCK_EX" in content, "Go program is missing syscall.LOCK_EX"


def test_go_source_has_real_flock_call_and_goroutine():
    checker = r'''
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "strconv"
)

func main() {
    fset := token.NewFileSet()
    f, err := parser.ParseFile(fset, "/home/user/aggregator.go", nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    syscallNames := map[string]bool{}
    for _, imp := range f.Imports {
        p, _ := strconv.Unquote(imp.Path.Value)
        if p == "syscall" {
            name := "syscall"
            if imp.Name != nil {
                name = imp.Name.Name
            }
            syscallNames[name] = true
        }
    }

    hasFlockCall := false
    hasLockEx := false
    hasGoroutine := false
    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.GoStmt:
            hasGoroutine = true
        case *ast.CallExpr:
            if sel, ok := x.Fun.(*ast.SelectorExpr); ok {
                if id, ok := sel.X.(*ast.Ident); ok && syscallNames[id.Name] && sel.Sel.Name == "Flock" {
                    hasFlockCall = true
                }
                // Permit standard helpers such as errgroup.Group.Go, which launch goroutines.
                if sel.Sel.Name == "Go" {
                    hasGoroutine = true
                }
            }
        case *ast.SelectorExpr:
            if id, ok := x.X.(*ast.Ident); ok && syscallNames[id.Name] && x.Sel.Name == "LOCK_EX" {
                hasLockEx = true
            }
        }
        return true
    })

    if !hasFlockCall || !hasLockEx || !hasGoroutine {
        fmt.Fprintf(os.Stderr, "required executable constructs missing: Flock call=%v LOCK_EX=%v goroutine=%v\n", hasFlockCall, hasLockEx, hasGoroutine)
        os.Exit(1)
    }
}
'''
    Path("/tmp/check_aggregator_ast.go").write_text(checker)
    result = subprocess.run(
        ["go", "run", "/tmp/check_aggregator_ast.go"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, result.stderr


def test_go_program_compiles():
    result = subprocess.run(
        ["go", "build", "-o", "/tmp/aggregator-under-test", AGGREGATOR_GO],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, f"aggregator.go does not compile:\n{result.stderr}"


def test_execute_pipeline_on_original_dataset():
    execute_pipeline()


def test_master_dataset_output():
    # This is the original canonical-output assertion, now checked only after run.sh executes.
    assert_objects_equal(read_output(), EXPECTED_ORIGINAL)


def test_pipeline_on_runtime_generated_files_and_symlinks():
    token = secrets.token_hex(8)
    generated_root = Path("/home/user/dataset") / ("verification_" + token)
    external_root = Path("/tmp") / ("external_" + token)
    generated_root.mkdir(parents=True)
    external_root.mkdir(parents=True)

    expected = list(EXPECTED_ORIGINAL)
    try:
        # Generate enough independently named files to exercise discovery and concurrent workers.
        for i in range(16):
            subdir = generated_root / ("nested_%02d" % (i % 4))
            subdir.mkdir(parents=True, exist_ok=True)
            first_id = f"{token}-{i:02d}-a"
            second_id = f"{token}-{i:02d}-b"
            measurement_a = f"{i + 10}.125"
            measurement_b = f"{i + 20}.875"
            timestamp_a = f"2026-09-12T12:{i:02d}:00Z"
            timestamp_b = f"2026-09-12T13:{i:02d}:30Z"
            (subdir / ("sample_%02d.dat" % i)).write_text(
                "##RAW_DATA runtime fixture\n"
                + f"{first_id}|{measurement_a}|{timestamp_a}\n"
                + "INVALID_ROW\n"
                + f"{second_id}|{measurement_b}|{timestamp_b}\n"
            )
            expected.extend([
                {"id": first_id, "measurement": measurement_a, "timestamp": timestamp_a},
                {"id": second_id, "measurement": measurement_b, "timestamp": timestamp_b},
            ])

        # Neither a .dat symlink nor files reached through a directory symlink are real
        # files within the dataset and therefore must not be processed.
        external_file = external_root / "decoy.dat"
        external_file.write_text(
            "##RAW_DATA\n"
            + f"DECOY-{token}|999|2099-01-01T00:00:00Z\n"
        )
        os.symlink(str(external_file), str(generated_root / "symlink_decoy.dat"))
        os.symlink(str(external_root), str(generated_root / "linked_directory"))

        execute_pipeline()
        assert_objects_equal(read_output(), expected)
    finally:
        shutil.rmtree(generated_root, ignore_errors=True)
        shutil.rmtree(external_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
