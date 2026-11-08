#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import secrets
import subprocess
import tempfile

BASE_DIR = "/home/user/ci_pipeline"


def test_makefile_fixed():
    makefile_path = os.path.join(BASE_DIR, "Makefile")
    assert os.path.isfile(makefile_path), f"{makefile_path} is missing."

    with open(makefile_path, 'r') as f:
        makefile_content = f.read()

    lines = makefile_content.splitlines()
    linking_line_found = False
    for line in lines:
        if "-o evaluator" in line and "main.o" in line and "expr_parser.o" in line:
            linking_line_found = True
            break

    assert linking_line_found, "Makefile linking step is not fixed. It should include expr_parser.o when building the evaluator executable."


def test_expr_parser_fixed():
    cpp_path = os.path.join(BASE_DIR, "expr_parser.cpp")
    assert os.path.isfile(cpp_path), f"{cpp_path} is missing."

    with open(cpp_path, 'r') as f:
        cpp_content = f.read()

    assert "return left - right;" in cpp_content, "The subtraction bug in expr_parser.cpp is not fixed. It should return 'left - right'."
    assert "return right - left;" not in cpp_content, "The original subtraction bug is still present in expr_parser.cpp."


def test_binary_built():
    binary_path = os.path.join(BASE_DIR, "evaluator")
    assert os.path.isfile(binary_path), f"The evaluator binary was not built at {binary_path}."

    st = os.stat(binary_path)
    assert st.st_mode & stat.S_IXUSR, f"The evaluator file at {binary_path} is not executable."


def test_test_results_log():
    log_path = os.path.join(BASE_DIR, "test_results.log")
    assert os.path.isfile(log_path), f"{log_path} is missing."

    with open(log_path, 'r') as f:
        log_content = f.read().strip()

    assert "ALL TESTS PASSED" in log_content, f"test_results.log does not contain 'ALL TESTS PASSED'. Content found: {log_content}"


def run_checked(command, timeout=30):
    return subprocess.run(
        command,
        cwd=BASE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )


def test_clean_rebuild_and_execute_evaluator():
    clean = run_checked(["make", "clean"])
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout.decode(errors='replace')}\n{clean.stderr.decode(errors='replace')}"
    assert not os.path.exists(os.path.join(BASE_DIR, "evaluator")), "make clean did not remove evaluator."
    assert not any(name.endswith(".o") for name in os.listdir(BASE_DIR)), "make clean did not remove object files."

    build = run_checked(["make"], timeout=60)
    assert build.returncode == 0, f"Clean make failed:\n{build.stdout.decode(errors='replace')}\n{build.stderr.decode(errors='replace')}"

    binary_path = os.path.join(BASE_DIR, "evaluator")
    assert os.path.isfile(binary_path), "make did not produce evaluator."
    assert os.access(binary_path, os.X_OK), "The rebuilt evaluator is not executable."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The rebuilt evaluator is not an ELF executable."

    symbols = subprocess.run(
        ["nm", "-C", binary_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        timeout=10,
    )
    assert symbols.returncode == 0, f"Could not inspect rebuilt evaluator symbols: {symbols.stderr.decode(errors='replace')}"
    symbol_text = symbols.stdout.decode(errors="replace")
    assert re.search(r"\bevaluate_expression\(.*\)", symbol_text), "The rebuilt evaluator does not link evaluate_expression from the parser."

    outputs = []
    for _ in range(3):
        result = run_checked(["./evaluator", "test"])
        assert result.returncode == 0, f"./evaluator test failed:\nstdout: {result.stdout.decode(errors='replace')}\nstderr: {result.stderr.decode(errors='replace')}"
        assert b"ALL TESTS PASSED" in result.stdout, f"./evaluator test did not report success: {result.stdout!r}"
        outputs.append(result.stdout)

    log_path = os.path.join(BASE_DIR, "test_results.log")
    assert os.path.isfile(log_path), "test_results.log is missing."
    with open(log_path, "rb") as f:
        logged_output = f.read()
    assert logged_output == outputs[0], f"test_results.log is not the exact standard output of ./evaluator test. Expected {outputs[0]!r}, found {logged_output!r}"


def test_parser_behavior_on_derived_inputs():
    rng = secrets.SystemRandom()
    cases = []
    for _ in range(12):
        left = rng.randint(-100000, 100000)
        right = rng.randint(-100000, 100000)
        if left == right:
            right += 1
        cases.append((f"{left} - {right}", left - right))

    harness = r'''#include "expr_parser.h"
#include <cstdlib>
#include <iostream>
#include <string>
int main(int argc, char **argv) {
    if (argc < 3 || ((argc - 1) % 2) != 0) return 2;
    for (int i = 1; i < argc; i += 2) {
        int actual = evaluate_expression(argv[i]);
        int expected = std::stoi(argv[i + 1]);
        if (actual != expected) {
            std::cerr << argv[i] << ": got " << actual << ", expected " << expected << "\n";
            return 1;
        }
    }
    return 0;
}
'''

    with tempfile.TemporaryDirectory() as tmp:
        harness_path = os.path.join(tmp, "parser_harness.cpp")
        harness_binary = os.path.join(tmp, "parser_harness")
        with open(harness_path, "w") as f:
            f.write(harness)

        compile_result = subprocess.run(
            ["g++", "-std=c++11", "-pthread", "-I", BASE_DIR,
             harness_path, os.path.join(BASE_DIR, "expr_parser.cpp"), "-o", harness_binary],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=30,
        )
        assert compile_result.returncode == 0, f"expr_parser.cpp could not be compiled with a test harness:\n{compile_result.stderr.decode(errors='replace')}"

        args = [harness_binary]
        for expression, expected in cases:
            args.extend([expression, str(expected)])
        result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False, timeout=15)
        assert result.returncode == 0, f"Parser failed derived subtraction cases:\n{result.stderr.decode(errors='replace')}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
