#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess

import pytest

HOME = "/home/user"
SOURCE = os.path.join(HOME, "processor.go")
BINARY = os.path.join(HOME, "processor")
QUERIES = os.path.join(HOME, "queries.txt")
RESULTS = os.path.join(HOME, "results.txt")
BUILT_BINARY = "/tmp/processor_built_by_verifier"
REFERENCE_BINARY = "/tmp/processor_reference"

EXPECTED_QUERIES = b"0.005\n0.012\n0.008\n120.0\n0.001\n"

REFERENCE_SOURCE = r'''package main

import (
    "bufio"
    "fmt"
    "os"
    "strconv"
)

func main() {
    if len(os.Args) < 2 {
        fmt.Println("Usage: processor <queries_file>")
        os.Exit(1)
    }

    file, err := os.Open(os.Args[1])
    if err != nil {
        panic(err)
    }
    defer file.Close()

    scanner := bufio.NewScanner(file)
    queryID := 1
    for scanner.Scan() {
        val, _ := strconv.ParseFloat(scanner.Text(), 64)
        target := float64(val)

        fmt.Printf("Processing query %d (target: %v)\n", queryID, target)

        var current float64 = 0.0
        var step float64 = 0.00001
        for current < target {
            next := current + step
            if next == current {
                panic("Livelock detected: step is too small to increment current value")
            }
            current = next
        }
        fmt.Printf("Success: %f\n", current)
        queryID++
    }
}
'''


def run(command, timeout=30):
    return subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )


def require_success(result, description):
    assert result.returncode == 0, (
        f"{description} failed with exit code {result.returncode}. "
        f"stderr: {result.stderr.decode(errors='replace')}"
    )


@pytest.fixture(scope="session", autouse=True)
def build_verification_binaries():
    with open(QUERIES, "rb") as f:
        assert f.read() == EXPECTED_QUERIES, "queries.txt was modified."

    built = run(["go", "build", "-o", BUILT_BINARY, "processor.go"], timeout=60)
    require_success(built, "Building processor.go")

    reference_path = "/tmp/reference_processor.go"
    with open(reference_path, "w") as f:
        f.write(REFERENCE_SOURCE)
    reference_build = run(["go", "build", "-o", REFERENCE_BINARY, reference_path], timeout=60)
    require_success(reference_build, "Building verifier reference processor")


def expected_output(input_path):
    result = run([REFERENCE_BINARY, input_path])
    require_success(result, "Reference processor execution")
    return result.stdout


def processor_output(binary, input_path):
    result = run([binary, input_path])
    require_success(result, f"Execution of {binary}")
    return result.stdout


def test_processor_go_fixed():
    path = "/home/user/processor.go"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    assert "float32" not in content, "The source code in processor.go still contains 'float32'. It should be completely replaced with 64-bit precision types."
    assert "float64" in content or "strconv.ParseFloat(scanner.Text(), 64)" in content, "The source code does not appear to use 64-bit precision (float64) as requested."


def test_processor_binary_exists():
    path = "/home/user/processor"
    assert os.path.isfile(path), f"Compiled binary {path} does not exist. Did you run 'go build'?"
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "processor is not a compiled ELF executable."
    metadata = run(["go", "version", "-m", path])
    require_success(metadata, "Inspecting processor as a Go binary")


def test_fixed_input_behavior():
    expected = expected_output(QUERIES)
    assert processor_output(BINARY, QUERIES) == expected, (
        "The submitted processor binary does not produce the required complete output."
    )
    assert processor_output(BUILT_BINARY, QUERIES) == expected, (
        "processor.go does not produce the required complete output when rebuilt."
    )


def test_additional_derived_inputs():
    rng = random.SystemRandom()
    values = [
        rng.randint(1, 900) / 100000,
        rng.randint(901, 9000) / 100000,
        rng.randint(9001, 250000) / 100000,
    ]
    input_path = "/tmp/verifier_queries.txt"
    with open(input_path, "w") as f:
        for value in values:
            f.write(format(value, ".5f") + "\n")

    expected = expected_output(input_path)
    assert processor_output(BINARY, input_path) == expected, (
        "The submitted processor binary failed additional derived queries."
    )
    assert processor_output(BUILT_BINARY, input_path) == expected, (
        "The rebuilt processor.go failed additional derived queries."
    )


def test_results_file_content():
    path = "/home/user/results.txt"
    assert os.path.isfile(path), f"Results file {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert "Processing query 4" in content, "results.txt is missing output for query 4."
    assert "Processing query 5" in content, "results.txt is missing output for query 5."

    # Check that the livelock was resolved and it successfully reached 120
    assert re.search(r"Success:\s*120\.000", content), "results.txt does not show successful completion for target 120.0 (query 4). Livelock might still be present."

    # Check that it successfully processed the final query
    assert re.search(r"Success:\s*0\.001000", content), "results.txt does not show successful completion for target 0.001 (query 5)."

    with open(path, "rb") as f:
        saved = f.read()
    expected = expected_output(QUERIES)
    actual = processor_output(BINARY, QUERIES)
    assert saved == expected, "results.txt is not the exact, complete expected standard output."
    assert saved == actual, "results.txt is not the exact standard output of the submitted processor binary."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
