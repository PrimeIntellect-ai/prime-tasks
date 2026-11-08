#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import struct
import subprocess

import pytest
from scapy.all import rdpcap, UDP, Raw

GO_PATH = "/home/user/statscalc/main.go"
BINARY_PATH = "/tmp/statscalc-submission"


def test_solution_txt():
    solution_path = "/home/user/solution.txt"
    assert os.path.exists(solution_path), f"File {solution_path} is missing."
    assert os.path.isfile(solution_path), f"{solution_path} is not a file."

    with open(solution_path, "r") as f:
        content = f.read().strip()

    assert content == "0.0141", f"Expected solution.txt to contain '0.0141', but got '{content}'"


def test_main_go_modified():
    assert os.path.exists(GO_PATH), f"File {GO_PATH} is missing."
    assert os.path.isfile(GO_PATH), f"{GO_PATH} is not a regular file."

    with open(GO_PATH, "r") as f:
        content = f.read()

    # Preserve the original task-requirement assertions.
    assert "float64" in content, "The Go code must use float64 internally for precision."
    assert "panic" in content, "The Go code must contain a panic statement to validate variance."
    assert "float32" in content, "The Go code should still decode values into float32 initially."


def test_real_negative_variance_assertion():
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

func isZero(e ast.Expr) bool {
    switch x := e.(type) {
    case *ast.BasicLit:
        v, err := strconv.ParseFloat(x.Value, 64)
        return err == nil && v == 0
    case *ast.ParenExpr:
        return isZero(x.X)
    case *ast.UnaryExpr:
        return (x.Op == token.ADD || x.Op == token.SUB) && isZero(x.X)
    case *ast.CallExpr:
        return len(x.Args) == 1 && isZero(x.Args[0])
    }
    return false
}

func conditionChecksBelowZero(e ast.Expr) bool {
    found := false
    ast.Inspect(e, func(n ast.Node) bool {
        b, ok := n.(*ast.BinaryExpr)
        if !ok { return true }
        if (b.Op == token.LSS && isZero(b.Y)) || (b.Op == token.GTR && isZero(b.X)) {
            found = true
        }
        return true
    })
    return found
}

func bodyPanics(body *ast.BlockStmt) bool {
    found := false
    ast.Inspect(body, func(n ast.Node) bool {
        call, ok := n.(*ast.CallExpr)
        if !ok { return true }
        id, ok := call.Fun.(*ast.Ident)
        if ok && id.Name == "panic" { found = true }
        return true
    })
    return found
}

func main() {
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil { panic(err) }
    valid := false
    ast.Inspect(f, func(n ast.Node) bool {
        stmt, ok := n.(*ast.IfStmt)
        if ok && conditionChecksBelowZero(stmt.Cond) && bodyPanics(stmt.Body) {
            valid = true
        }
        return true
    })
    if !valid {
        fmt.Fprintln(os.Stderr, "no executable panic assertion guarding a below-zero value was found")
        os.Exit(1)
    }
}
'''
    checker_path = "/tmp/check_stats_ast.go"
    with open(checker_path, "w") as f:
        f.write(checker)
    subprocess.run(
        ["go", "run", checker_path, GO_PATH],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )


@pytest.fixture(scope="session")
def compiled_program():
    result = subprocess.run(
        ["go", "build", "-o", BINARY_PATH, GO_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"main.go did not compile:\n{result.stderr}"
    return BINARY_PATH


def welford(values):
    count = 0
    mean = 0.0
    m2 = 0.0
    for value in values:
        count += 1
        delta = value - mean
        mean += delta / count
        delta2 = value - mean
        m2 += delta * delta2
    return math.sqrt(m2 / count)


def encode_float32(value):
    raw = struct.pack(">f", value)
    return raw.hex(), struct.unpack(">f", raw)[0]


def run_program(binary, hex_lines):
    proc = subprocess.run(
        [binary],
        input="\n".join(hex_lines) + "\n",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert proc.returncode == 0, f"program failed:\n{proc.stderr}"
    output = proc.stdout.strip()
    assert re.fullmatch(r"\d+\.\d{4}", output), \
        f"expected one finite number with exactly four decimal places, got {output!r}"
    return float(output), output


def assert_dataset(binary, requested_values):
    encoded = [encode_float32(v) for v in requested_values]
    actual, _ = run_program(binary, [item[0] for item in encoded])
    expected = welford([item[1] for item in encoded])
    tolerance = max(0.000051, abs(expected) * 2e-8)
    assert abs(actual - expected) <= tolerance, \
        f"expected standard deviation near {expected}, got {actual}"


def test_program_on_pcap_payloads(compiled_program):
    payloads = []
    values = []
    for packet in rdpcap("/home/user/telemetry.pcap"):
        if UDP in packet and packet[UDP].dport == 9000 and Raw in packet:
            raw = bytes(packet[Raw].load)
            assert len(raw) == 4
            payloads.append(raw.hex())
            values.append(struct.unpack(">f", raw)[0])

    assert payloads, "no UDP destination-port-9000 payloads found"
    actual, rendered = run_program(compiled_program, payloads)
    expected = welford(values)
    assert abs(actual - expected) <= 0.000051
    assert rendered == "0.0141"


def test_hex_decoding_and_population_variance(compiled_program):
    assert_dataset(compiled_program, [1.0, 2.0, 3.0, 4.0, 8.0])


def test_numerically_difficult_inputs(compiled_program):
    # Runtime-generated order and offsets prevent a fixed-output implementation
    # and expose the cancellation in the original sum-of-squares algorithm.
    rng = random.SystemRandom()
    for base, step in [(1e12, 131072.0), (1e15, 134217728.0)]:
        offsets = list(range(-7, 8))
        rng.shuffle(offsets)
        values = [base + step * i for i in offsets]
        assert_dataset(compiled_program, values)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
