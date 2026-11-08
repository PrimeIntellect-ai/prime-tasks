#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import re
import secrets
import struct
import subprocess
import sys
import tempfile


def checksum(expr):
    return sum(ord(ch) for ch in expr) % 256


def test_evaluator_c_fixed():
    path = "/home/user/evaluator.c"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert re.search(r"malloc\s*\(\s*strlen\s*\(\s*expr\s*\)\s*\+\s*1\s*\)", content) or \
           re.search(r"malloc\s*\(\s*1\s*\+\s*strlen\s*\(\s*expr\s*\)\s*\)", content) or \
           re.search(r"strdup\s*\(\s*expr\s*\)", content) or \
           re.search(r"calloc\s*\(", content), \
           f"Buffer allocation bug not fixed in {path} (expected malloc(strlen(expr) + 1) or equivalent)."

    assert re.search(r"free\s*\(\s*expr_copy\s*\)", content), \
        f"Memory leak not fixed in {path} (expected free(expr_copy))."


def test_libeval_so_exists():
    path = "/home/user/libeval.so"
    assert os.path.isfile(path), f"Shared library {path} does not exist."


def test_output_json():
    path = "/home/user/output.json"
    assert os.path.isfile(path), f"Output file {path} does not exist."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{path} is not a valid JSON file."

    expected_results = {
        "3 4 + 2 *": 14.0,
        "5 2 * 3 +": 13.0,
        "10 5 * 20 + 2 *": 140.0,
    }

    assert isinstance(data, dict), "Expected JSON root to be a dictionary."
    for expr, expected_result in expected_results.items():
        assert expr in data, f"Expression '{expr}' missing from {path}."
        assert isinstance(data[expr], dict), f"Entry for '{expr}' must be a dictionary."
        assert data[expr].get("checksum") == checksum(expr), \
            f"Checksum for '{expr}' is incorrect."
        actual_result = data[expr].get("result")
        assert isinstance(actual_result, (int, float)), \
            f"Result for '{expr}' must be a number."
        assert abs(actual_result - expected_result) < 1e-6, \
            f"Result for '{expr}' is incorrect. Expected {expected_result}, got {actual_result}."


def test_runtime_memory_safety():
    harness = r'''
#include <math.h>
#include <stdlib.h>
#include <string.h>

double evaluate_postfix(const char *expr);

int main(void) {
    char *expr = malloc(6000);
    if (!expr) return 2;
    memset(expr, '0', 5000);
    strcpy(expr + 5000, "7 11 +");

    for (int i = 0; i < 64; ++i) {
        double value = evaluate_postfix(expr);
        if (fabs(value - 18.0) > 1e-9) return 3;
    }
    free(expr);
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        harness_path = os.path.join(td, "harness.c")
        binary_path = os.path.join(td, "harness")
        with open(harness_path, "w") as f:
            f.write(harness)

        build = subprocess.run([
            "gcc", "-O0", "-g", "-fsanitize=address", "-fno-omit-frame-pointer",
            "/home/user/evaluator.c", harness_path, "-lm", "-o", binary_path
        ], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
        assert build.returncode == 0, f"evaluator.c did not compile with AddressSanitizer:\n{build.stderr}"

        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1:exitcode=99"
        run = subprocess.run([binary_path], text=True, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, env=env, timeout=30)
        assert run.returncode == 0, \
            f"The evaluator failed functional or memory-safety checks:\n{run.stdout}\n{run.stderr}"


def test_orchestrator_end_to_end():
    orchestrator = "/home/user/orchestrator.py"
    source_path = "/home/user/evaluator.c"
    input_path = "/home/user/input.txt"
    output_path = "/home/user/output.json"
    library_path = "/home/user/libeval.so"

    assert os.path.isfile(orchestrator), f"File {orchestrator} does not exist."

    a, b, c, d, e, f, g = [secrets.randbelow(30) + 2 for _ in range(7)]
    cases = {
        f"{a} {b} + {c} *": float((a + b) * c),
        f"{d} {e} * {f} + 2 *": float((d * e + f) * 2),
        ("0" * 4096) + f"{g} 11 +": float(g + 11),
    }

    with open(source_path, "rb") as fobj:
        original_source = fobj.read()

    canary_value = secrets.randbits(60) + 1
    canary_source = (
        "\nunsigned long long verifier_build_canary(void) { "
        f"return {canary_value}ULL; }}\n"
    ).encode("ascii")

    try:
        with open(source_path, "wb") as fobj:
            fobj.write(original_source)
            fobj.write(canary_source)

        with open(input_path, "w", newline="\n") as fobj:
            for expr in cases:
                fobj.write(expr + "\n")

        for path in (output_path, library_path):
            if os.path.lexists(path):
                os.remove(path)

        run = subprocess.run([sys.executable, orchestrator], cwd="/home/user",
                             text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             timeout=60)
        assert run.returncode == 0, \
            f"orchestrator.py failed:\n{run.stdout}\n{run.stderr}"

        assert os.path.isfile(library_path), "orchestrator.py did not create libeval.so."
        assert os.path.isfile(output_path), "orchestrator.py did not create output.json."

        with open(library_path, "rb") as fobj:
            elf_header = fobj.read(20)
        assert elf_header[:4] == b"\x7fELF", "libeval.so is not an ELF library."
        assert len(elf_header) >= 18, "libeval.so has a truncated ELF header."
        byte_order = "<" if elf_header[5] == 1 else ">" if elf_header[5] == 2 else None
        assert byte_order is not None, "libeval.so has an invalid ELF byte order."
        assert struct.unpack(byte_order + "H", elf_header[16:18])[0] == 3, \
            "libeval.so is not an ELF shared object."

        lib = ctypes.CDLL(library_path)
        lib.verifier_build_canary.argtypes = []
        lib.verifier_build_canary.restype = ctypes.c_ulonglong
        assert lib.verifier_build_canary() == canary_value, \
            "libeval.so was not compiled from /home/user/evaluator.c by the orchestrator."

        lib.evaluate_postfix.argtypes = [ctypes.c_char_p]
        lib.evaluate_postfix.restype = ctypes.c_double
        for expr, expected in cases.items():
            actual = lib.evaluate_postfix(expr.encode("ascii"))
            assert abs(actual - expected) < 1e-6, \
                f"Compiled evaluator returned {actual} for '{expr}', expected {expected}."

        with open(output_path, "r") as fobj:
            data = json.load(fobj)
        assert isinstance(data, dict), "Expected JSON root to be a dictionary."
        assert set(data) == set(cases), \
            "output.json does not contain exactly the expressions from input.txt."

        for expr, expected_result in cases.items():
            entry = data[expr]
            assert isinstance(entry, dict), f"Entry for '{expr}' must be a dictionary."
            assert entry.get("checksum") == checksum(expr), \
                f"Checksum for '{expr}' is incorrect."
            result = entry.get("result")
            assert isinstance(result, (int, float)), f"Result for '{expr}' must be numeric."
            assert abs(result - expected_result) < 1e-6, \
                f"Result for '{expr}' is incorrect. Expected {expected_result}, got {result}."
    finally:
        with open(source_path, "wb") as fobj:
            fobj.write(original_source)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
