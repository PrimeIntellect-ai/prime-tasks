#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess

import pytest


def run(cmd, **kwargs):
    kwargs.setdefault("timeout", 30)
    kwargs.setdefault("stdout", subprocess.PIPE)
    kwargs.setdefault("stderr", subprocess.PIPE)
    kwargs.setdefault("text", True)
    result = subprocess.run(cmd, **kwargs)
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {' '.join(cmd)}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def decode_records(data):
    records = []
    offset = 0
    while offset < len(data):
        length = data[offset]
        offset += 1
        assert offset + length <= len(data), "data.bin contains a truncated record"
        payload = data[offset:offset + length]
        offset += length
        records.append(payload.decode("ascii"))
    return records


def test_data_bin_exists_and_size():
    path = "/home/user/data.bin"
    assert os.path.isfile(path), f"File {path} is missing. Did you run the Go generator?"

    # Calculate expected size:
    # 10 events (0-9): 1 byte len + 7 bytes string = 8 bytes each -> 80 bytes
    # 40 events (10-49): 1 byte len + 8 bytes string = 9 bytes each -> 360 bytes
    # Total = 440 bytes
    expected_size = 440
    actual_size = os.path.getsize(path)
    assert actual_size == expected_size, f"Expected {path} to be {expected_size} bytes, got {actual_size} bytes."


def test_parser_executable_exists():
    path = "/home/user/parser"
    assert os.path.isfile(path), f"Executable {path} is missing. Did you compile the C++ parser?"
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_decoded_log_content():
    path = "/home/user/decoded.log"
    assert os.path.isfile(path), f"File {path} is missing. Did you run the parser and redirect output?"

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 50, f"Expected exactly 50 lines in {path}, got {len(lines)}."

    expected_lines = sorted([f"Parsed: Event-{i}" for i in range(50)])

    assert lines == expected_lines, f"The contents of {path} do not match the expected sorted output."


def test_generator_source_uses_required_synchronization():
    checker = r'''
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)

func main() {
    if len(os.Args) != 2 { os.Exit(2) }
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil { panic(err) }
    add, done, wait, closeCalls := 0, 0, 0, 0
    ast.Inspect(f, func(n ast.Node) bool {
        call, ok := n.(*ast.CallExpr)
        if !ok { return true }
        if id, ok := call.Fun.(*ast.Ident); ok && id.Name == "close" {
            closeCalls++
        }
        if sel, ok := call.Fun.(*ast.SelectorExpr); ok {
            switch sel.Sel.Name {
            case "Add": add++
            case "Done": done++
            case "Wait": wait++
            }
        }
        return true
    })
    if add < 1 || done < 1 || wait < 1 || closeCalls < 1 {
        fmt.Fprintf(os.Stderr, "missing synchronization calls: Add=%d Done=%d Wait=%d close=%d\n", add, done, wait, closeCalls)
        os.Exit(1)
    }
}
'''
    with open("/tmp/check_generate_ast.go", "w") as f:
        f.write(checker)
    run(["go", "build", "-o", "/tmp/check_generate_ast", "/tmp/check_generate_ast.go"])
    run(["/tmp/check_generate_ast", "/home/user/generate.go"])


def test_freshly_built_generator_completes_pipeline():
    run(["go", "build", "-o", "/tmp/generator_from_source", "/home/user/generate.go"])
    expected = [f"Event-{i}" for i in range(50)]

    # Repeated execution catches generators that still exit before their workers
    # and consumer have completed.
    for _ in range(4):
        try:
            os.remove("/home/user/data.bin")
        except FileNotFoundError:
            pass
        run(["/tmp/generator_from_source"], cwd="/home/user")
        with open("/home/user/data.bin", "rb") as f:
            data = f.read()
        assert len(data) == 440
        assert sorted(decode_records(data)) == sorted(expected)


def make_random_parser_input(path):
    alphabet = string.ascii_letters + string.digits + "_-.:"
    values = []
    for i in range(31):
        length = 3 + secrets.randbelow(70)
        value = "Probe_%02d_" % i + "".join(secrets.choice(alphabet) for _ in range(length))
        values.append(value)
    with open(path, "wb") as f:
        for value in values:
            payload = value.encode("ascii")
            assert len(payload) < 256
            f.write(bytes([len(payload)]))
            f.write(payload)
    return values


def assert_parser_output(executable, input_path, values, env=None):
    result = run([executable, input_path], env=env)
    expected = [f"Parsed: {value}" for value in values]
    assert result.stdout.splitlines() == expected


def test_parser_binary_and_repaired_source_on_derived_input():
    input_path = "/tmp/random_events.bin"
    values = make_random_parser_input(input_path)

    # Exercise the executable the agent was instructed to produce.
    assert_parser_output("/home/user/parser", input_path, values)

    # Rebuild the submitted source with sanitizers so the allocation, bounds,
    # and deallocation repairs are checked rather than trusting a stale binary.
    run([
        "g++", "-O1", "-g", "-fsanitize=address,undefined",
        "-fno-omit-frame-pointer", "/home/user/parser.cpp",
        "-o", "/tmp/parser_from_source"
    ])
    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1"
    env["UBSAN_OPTIONS"] = "halt_on_error=1:print_stacktrace=1"
    assert_parser_output("/tmp/parser_from_source", input_path, values, env=env)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
