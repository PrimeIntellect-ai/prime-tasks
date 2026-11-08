#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess
import tempfile
import pytest

PROJECT = "/home/user/web_eval"
SERVER = os.path.join(PROJECT, "server")
LIBRARY = os.path.join(PROJECT, "parser/target/release/libparser.a")
LOG = os.path.join(PROJECT, "output.log")


def test_output_log_exists_and_correct():
    assert os.path.isfile(LOG), f"Output log file {LOG} does not exist. The server must be executed and output redirected."
    with open(LOG, "r") as f:
        content = f.read().strip()
    expected = "14.000000"
    assert content == expected, f"Expected output log to contain '{expected}', but found '{content}'."


def test_server_executable_exists():
    assert os.path.isfile(SERVER), f"Server executable {SERVER} does not exist. The Makefile should compile it."
    assert os.access(SERVER, os.X_OK), f"Server file {SERVER} is not executable."


def test_rust_library_compiled():
    assert os.path.isfile(LIBRARY), f"Rust static library {LIBRARY} does not exist. The Makefile should build the Rust project in release mode."


def run_number(executable, expression):
    proc = subprocess.run(
        [executable, expression], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert proc.returncode == 0, f"{executable} failed for {expression!r}: {proc.stderr}"
    output = proc.stdout.strip()
    assert len(output.splitlines()) == 1, f"Expected one output line, got {output!r}"
    try:
        return float(output)
    except ValueError:
        pytest.fail(f"Output is not a number for {expression!r}: {output!r}")


def generated_cases():
    rng = random.SystemRandom()
    cases = [("5 1 2 + 4 * + 3 -", 14.0)]
    operators = ["+", "-", "*", "/"]
    for _ in range(12):
        a = rng.randint(-20, 20)
        b = rng.choice([n for n in range(-12, 13) if n != 0])
        c = rng.choice([n for n in range(-12, 13) if n != 0])
        d = rng.choice([n for n in range(-12, 13) if n != 0])
        op1, op2, op3 = [rng.choice(operators) for _ in range(3)]

        value = float(a)
        for operand, op in ((b, op1), (c, op2), (d, op3)):
            if op == "+":
                value += operand
            elif op == "-":
                value -= operand
            elif op == "*":
                value *= operand
            else:
                value /= operand
        cases.append((f"{a} {b} {op1} {c} {op2} {d} {op3}", value))
    return cases


def test_make_rebuilds_and_artifacts_really_work():
    # Remove the claimed products so passing requires the submitted Makefile to
    # rebuild both the release Rust library and the C server.
    if os.path.exists(SERVER):
        os.remove(SERVER)
    if os.path.exists(LIBRARY):
        os.remove(LIBRARY)

    proc = subprocess.run(
        ["make"], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180
    )
    assert proc.returncode == 0, f"make failed:\n{proc.stdout}"

    assert os.path.isfile(SERVER), "make did not create server"
    assert os.access(SERVER, os.X_OK), "make did not create an executable server"
    assert os.path.isfile(LIBRARY), "make did not create parser/target/release/libparser.a"

    with open(SERVER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "server is not a compiled ELF executable"
    with open(LIBRARY, "rb") as f:
        assert f.read(8) == b"!<arch>\n", "libparser.a is not a static archive"

    cases = generated_cases()
    for expression, expected in cases:
        actual = run_number(SERVER, expression)
        assert math.isclose(actual, expected, rel_tol=1e-6, abs_tol=1e-6), (
            f"server evaluated {expression!r} as {actual}, expected {expected}"
        )

    # Link an independent C caller directly against the produced Rust archive,
    # ensuring the archive exports and implements the required FFI function.
    with tempfile.TemporaryDirectory() as td:
        source = os.path.join(td, "ffi_test.c")
        harness = os.path.join(td, "ffi_test")
        with open(source, "w") as f:
            f.write(r'''#include <stdio.h>
extern double evaluate_rpn(const char *expr);
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    printf("%.17g\n", evaluate_rpn(argv[1]));
    return 0;
}
''')
        link = subprocess.run(
            ["gcc", source, LIBRARY, "-o", harness, "-lpthread", "-ldl", "-lm"],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60
        )
        assert link.returncode == 0, (
            "The Rust static library could not be linked through evaluate_rpn:\n" + link.stdout
        )
        for expression, expected in cases:
            actual = run_number(harness, expression)
            assert math.isclose(actual, expected, rel_tol=1e-9, abs_tol=1e-9), (
                f"Rust FFI evaluated {expression!r} as {actual}, expected {expected}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
