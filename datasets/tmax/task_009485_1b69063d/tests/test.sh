#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_TEST_EOF' > /home/user/interp/zz_verifier_ring_test.go
package main

import (
    "reflect"
    "testing"
)

func TestVerifierRingTapeBehavior(t *testing.T) {
    tape := NewRingTape()
    if tape == nil {
        t.Fatal("NewRingTape returned nil")
    }
    value := reflect.ValueOf(tape)
    switch value.Kind() {
    case reflect.Chan, reflect.Func, reflect.Interface, reflect.Map, reflect.Ptr, reflect.Slice:
        if value.IsNil() {
            t.Fatal("NewRingTape returned a typed nil")
        }
    }

    // Fill all 256 cells with distinct byte values and return to cell zero.
    for i := 0; i < 256; i++ {
        tape.Write(byte(i))
        tape.MoveRight()
    }
    if got := tape.Read(); got != 0 {
        t.Fatalf("moving right 256 times did not wrap to cell 0: got %d", got)
    }

    // Moving left from cell zero must reach cell 255.
    tape.MoveLeft()
    if got := tape.Read(); got != 255 {
        t.Fatalf("moving left from cell 0 did not wrap to cell 255: got %d", got)
    }
    tape.MoveRight()
    if got := tape.Read(); got != 0 {
        t.Fatalf("moving right from cell 255 did not wrap to cell 0: got %d", got)
    }

    tape.Dec()
    if got := tape.Read(); got != 255 {
        t.Fatalf("Dec did not wrap byte 0 to 255: got %d", got)
    }
    tape.Inc()
    if got := tape.Read(); got != 0 {
        t.Fatalf("Inc did not wrap byte 255 to 0: got %d", got)
    }
    tape.Write(73)
    if got := tape.Read(); got != 73 {
        t.Fatalf("Write/Read mismatch: got %d, want 73", got)
    }
}
GO_TEST_EOF
trap 'rm -f /home/user/interp/zz_verifier_ring_test.go' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

PROJECT_DIR = "/home/user/interp"


def run(cmd, **kwargs):
    return subprocess.run(cmd, **kwargs)


def test_build_tags():
    tape_linux_path = os.path.join(PROJECT_DIR, "tape_linux.go")
    tape_windows_path = os.path.join(PROJECT_DIR, "tape_windows.go")

    assert os.path.isfile(tape_linux_path), f"Missing {tape_linux_path}"
    with open(tape_linux_path, "r") as f:
        linux_content = f.read()
    assert "//go:build linux" in linux_content and "windows" not in linux_content.split('\n')[0], "tape_linux.go does not have the correct //go:build linux tag."

    assert os.path.isfile(tape_windows_path), f"Missing {tape_windows_path}"
    with open(tape_windows_path, "r") as f:
        windows_content = f.read()
    assert "//go:build windows" in windows_content and "!" not in windows_content.split('\n')[0], "tape_windows.go does not have the correct //go:build windows tag."


def test_ring_tape_behavior():
    result = run(
        ["go", "test", "-run", "^TestVerifierRingTapeBehavior$", "-count=1"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"RingTape behavioral tests failed:\n{result.stdout}\n{result.stderr}"


def test_make_builds():
    res_linux = run(["make", "build-linux"], cwd=PROJECT_DIR, capture_output=True, text=True, timeout=60)
    assert res_linux.returncode == 0, f"make build-linux failed:\n{res_linux.stderr}"
    linux_binary = os.path.join(PROJECT_DIR, "interp-linux")
    assert os.path.isfile(linux_binary), "interp-linux binary was not created."
    with open(linux_binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "interp-linux is not a Linux ELF binary"

    res_windows = run(["make", "build-windows"], cwd=PROJECT_DIR, capture_output=True, text=True, timeout=60)
    assert res_windows.returncode == 0, f"make build-windows failed:\n{res_windows.stderr}"
    windows_binary = os.path.join(PROJECT_DIR, "interp-windows.exe")
    assert os.path.isfile(windows_binary), "interp-windows.exe binary was not created."
    with open(windows_binary, "rb") as f:
        assert f.read(2) == b"MZ", "interp-windows.exe is not a Windows executable"


def test_output_dat_and_actual_input_processing():
    output_dat_path = os.path.join(PROJECT_DIR, "output.dat")
    assert os.path.isfile(output_dat_path), f"output.dat is missing at {output_dat_path}"

    with open(output_dat_path, "r") as f:
        content = f.read()
    assert content == "Hello World!\n", f"output.dat does not contain the expected output. Got: {repr(content)}"

    with open(os.path.join(PROJECT_DIR, "input.df"), "rb") as f:
        input_script = f.read()
    with open(output_dat_path, "rb") as f:
        saved_output = f.read()

    result = run(
        [os.path.join(PROJECT_DIR, "interp-linux")],
        cwd=PROJECT_DIR,
        input=input_script,
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, f"interp-linux failed on input.df: {result.stderr!r}"
    assert result.stdout == saved_output, "output.dat is not the actual output of interp-linux processing input.df"


def reference_straight_line(code):
    cells = bytearray(256)
    ptr = 0
    output = bytearray()
    for op in code:
        if op == 62:       # >
            ptr = (ptr + 1) % 256
        elif op == 60:     # <
            ptr = (ptr - 1) % 256
        elif op == 43:     # +
            cells[ptr] = (cells[ptr] + 1) % 256
        elif op == 45:     # -
            cells[ptr] = (cells[ptr] - 1) % 256
        elif op == 46:     # .
            output.append(cells[ptr])
    return bytes(output)


def test_interpreter_on_derived_inputs():
    binary = os.path.join(PROJECT_DIR, "interp-linux")
    alphabet = b"><+-."
    for _ in range(4):
        random_part = bytes(alphabet[secrets.randbelow(len(alphabet))] for _ in range(600))
        # Force both pointer-edge and byte-edge wrapping in every case.
        code = b"<+.>-." + random_part + b"."
        expected = reference_straight_line(code)
        result = run([binary], cwd=PROJECT_DIR, input=code, capture_output=True, timeout=10)
        assert result.returncode == 0, f"interp-linux failed on generated input: {result.stderr!r}"
        assert result.stdout == expected, "interp-linux produced an incorrect result for a verifier-derived program"


def benchmark_body(source):
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    source = re.sub(r"//[^\n]*", "", source)
    match = re.search(r"func\s+BenchmarkTape\s*\([^)]*\)\s*\{", source)
    assert match, "tape_test.go does not define BenchmarkTape"
    start = match.end() - 1
    depth = 0
    for pos in range(start, len(source)):
        if source[pos] == "{":
            depth += 1
        elif source[pos] == "}":
            depth -= 1
            if depth == 0:
                return source[start + 1:pos]
    raise AssertionError("BenchmarkTape has an unterminated body")


def test_benchmark_exists_and_runs():
    tape_test_path = os.path.join(PROJECT_DIR, "tape_test.go")
    assert os.path.isfile(tape_test_path), f"Missing {tape_test_path}"
    with open(tape_test_path, "r") as f:
        body = benchmark_body(f.read())
    assert "b.N" in body, "BenchmarkTape does not use the benchmark iteration count b.N"
    assert re.search(r"\.\s*Inc\s*\(", body), "BenchmarkTape does not call Inc()"
    assert re.search(r"\.\s*MoveRight\s*\(", body), "BenchmarkTape does not call MoveRight()"

    result = run(
        ["go", "test", "-run", "^$", "-bench", "^BenchmarkTape$", "-count=1"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f"BenchmarkTape does not run successfully:\n{result.stdout}\n{result.stderr}"
    assert re.search(r"^BenchmarkTape(?:-\d+)?\s+\d+\s+[0-9.]+\s+ns/op", result.stdout, re.M), "go test did not execute BenchmarkTape"


def test_bench_txt():
    bench_txt_path = os.path.join(PROJECT_DIR, "bench.txt")
    assert os.path.isfile(bench_txt_path), f"bench.txt is missing at {bench_txt_path}"

    with open(bench_txt_path, "r") as f:
        content = f.read()

    assert "BenchmarkTape" in content, "bench.txt does not contain 'BenchmarkTape'"
    assert "ns/op" in content, "bench.txt does not contain 'ns/op'"
    assert re.search(r"^BenchmarkTape(?:-\d+)?\s+\d+\s+[0-9.]+\s+ns/op", content, re.M), "bench.txt does not contain a valid BenchmarkTape result line"
    assert re.search(r"^PASS$", content, re.M), "bench.txt is not complete successful go test benchmark output"

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
