#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/check_concurrency.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)

func main() {
    if len(os.Args) != 2 {
        fmt.Fprintln(os.Stderr, "usage: check_concurrency <go-file>")
        os.Exit(2)
    }
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }

    found := false
    concurrent := false
    validSignature := false
    for _, decl := range f.Decls {
        fn, ok := decl.(*ast.FuncDecl)
        if !ok || fn.Recv != nil || fn.Name.Name != "ComputeSumOfSquares" {
            continue
        }
        found = true
        validSignature = fn.Type.Params != nil && len(fn.Type.Params.List) == 1 &&
            fn.Type.Results != nil && len(fn.Type.Results.List) == 1
        if validSignature {
            arr, ok := fn.Type.Params.List[0].Type.(*ast.ArrayType)
            validSignature = ok && arr.Len == nil
            if validSignature {
                inType, ok := arr.Elt.(*ast.Ident)
                validSignature = ok && inType.Name == "float64"
            }
            if validSignature {
                outType, ok := fn.Type.Results.List[0].Type.(*ast.Ident)
                validSignature = ok && outType.Name == "float64"
            }
        }
        ast.Inspect(fn.Body, func(n ast.Node) bool {
            if _, ok := n.(*ast.GoStmt); ok {
                concurrent = true
            }
            return true
        })
    }

    if !found || !validSignature || !concurrent {
        fmt.Fprintf(os.Stderr, "found=%v validSignature=%v concurrent=%v\n", found, validSignature, concurrent)
        os.Exit(1)
    }
}
GO_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess
import tempfile
import pytest

GO_FILE = "/home/user/app/sensor_agg.go"
INPUT_FILE = "/home/user/data/input.json"
APP_BIN = "/home/user/app/app_bin"


def test_anomaly_time():
    time_file = "/home/user/anomaly_time.txt"
    assert os.path.isfile(time_file), f"File {time_file} does not exist."
    with open(time_file, "r") as f:
        content = f.read().strip()

    assert content == "2023-11-01T10:05:05Z", f"Incorrect anomaly time extracted. Expected '2023-11-01T10:05:05Z', got '{content}'."

    anomaly_lines = []
    for name in ("service1.log", "service2.log", "service3.log"):
        with open(os.path.join("/home/user/logs", name), "r") as f:
            anomaly_lines.extend(line.strip() for line in f if "CRITICAL_ANOMALY" in line)
    assert len(anomaly_lines) == 1, f"Expected exactly one anomaly log line, got {anomaly_lines}"
    parts = anomaly_lines[0].split()
    derived = parts[0].replace("/", "-") + "T" + parts[1] + "Z"
    assert content == derived, f"anomaly_time.txt does not match the timestamp in the logs: {derived}"


def test_output_json_validity_and_content():
    output_file = "/home/user/output.json"
    assert os.path.isfile(output_file), f"File {output_file} does not exist."

    with open(output_file, "r") as f:
        content = f.read().strip()

    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"Content of {output_file} is not valid JSON: {content}")

    assert "batch_id" in data, "output.json missing 'batch_id' field."
    assert "variance" in data, "output.json missing 'variance' field."
    assert data["batch_id"] == "A1", f"Expected batch_id 'A1', got {data['batch_id']}"
    variance = data["variance"]
    assert isinstance(variance, (int, float)), f"Variance should be a numeric type, got {type(variance).__name__}"
    assert abs(variance - 34.5) < 0.001, f"Expected variance 34.5, got {variance}"


def test_go_race_condition():
    assert os.path.isfile(GO_FILE), f"File {GO_FILE} does not exist."
    cmd = ["go", "run", "-race", GO_FILE, INPUT_FILE]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)

    if "WARNING: DATA RACE" in result.stderr or "WARNING: DATA RACE" in result.stdout:
        pytest.fail("Data race condition still present in sensor_agg.go.")
    assert result.returncode == 0, f"Go program failed to execute correctly:\n{result.stderr}"

    output = result.stdout.strip()
    try:
        data = json.loads(output)
        assert data.get("variance") == 34.5, f"Go program output incorrect variance: {output}"
    except json.JSONDecodeError:
        pytest.fail(f"Go program output is not valid JSON: {output}")


def run_case(executable, batch_id, readings, race=False):
    expected = sum(v * v for v in readings)
    fd, path = tempfile.mkstemp(prefix="sensor-input-", suffix=".json")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump({"batch_id": batch_id, "readings": readings}, f)
        env = os.environ.copy()
        if race:
            env["GORACE"] = "halt_on_error=1"
        result = subprocess.run([executable, path], capture_output=True, text=True, env=env, timeout=120)
        combined = result.stdout + result.stderr
        assert "WARNING: DATA RACE" not in combined, f"Race detector reported a data race:\n{combined}"
        assert result.returncode == 0, f"Program failed for generated input:\n{combined}"
        try:
            data = json.loads(result.stdout.strip())
        except json.JSONDecodeError:
            pytest.fail(f"Program output is not valid JSON: {result.stdout!r}")
        assert data.get("batch_id") == batch_id, f"Incorrect batch_id for generated input: {data}"
        value = data.get("variance")
        assert isinstance(value, (int, float)) and not isinstance(value, bool), f"variance is not numeric: {data}"
        assert abs(value - expected) <= 1e-9 * max(1.0, abs(expected)), f"Expected {expected}, got {value}"
    finally:
        os.unlink(path)


def generated_cases():
    rng = random.SystemRandom()
    token = secrets.token_hex(12)
    return [
        ("empty-" + token, []),
        ("fractional-" + token, [rng.randrange(-80, 81) / 4.0 for _ in range(257)]),
        ("stress-" + token, [rng.randrange(-100, 101) for _ in range(20000)]),
    ]


def test_built_app_exists_and_handles_generated_inputs():
    assert os.path.isfile(APP_BIN), f"Required built application {APP_BIN} does not exist."
    assert os.access(APP_BIN, os.X_OK), f"{APP_BIN} is not executable."
    with open(APP_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{APP_BIN} is not a built ELF executable."
    version = subprocess.run(["go", "version", "-m", APP_BIN], capture_output=True, text=True, timeout=30)
    assert version.returncode == 0 and "go1." in version.stdout, f"{APP_BIN} is not recognized as a Go build:\n{version.stdout}{version.stderr}"
    for batch_id, readings in generated_cases():
        run_case(APP_BIN, batch_id, readings)


def test_source_is_concurrent_and_race_free_on_generated_inputs():
    assert os.path.isfile(GO_FILE), f"File {GO_FILE} does not exist."
    checker = subprocess.run(["go", "build", "-o", "/tmp/check_concurrency", "/tmp/check_concurrency.go"], capture_output=True, text=True, timeout=60)
    assert checker.returncode == 0, f"Could not build concurrency checker:\n{checker.stderr}"
    checked = subprocess.run(["/tmp/check_concurrency", GO_FILE], capture_output=True, text=True, timeout=30)
    assert checked.returncode == 0, "ComputeSumOfSquares must retain its []float64 -> float64 signature and use concurrent goroutine processing.\n" + checked.stderr

    built = subprocess.run(["go", "build", "-race", "-o", "/tmp/sensor_agg_race", GO_FILE], capture_output=True, text=True, timeout=120)
    assert built.returncode == 0, f"Failed to build source with race detector:\n{built.stderr}"
    for batch_id, readings in generated_cases():
        run_case("/tmp/sensor_agg_race", batch_id, readings, race=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
