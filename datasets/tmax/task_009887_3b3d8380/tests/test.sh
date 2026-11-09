#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

BASE_DIR = "/home/user/calcgraph"
RESULTS_LOG = "/home/user/results.log"
RUN_TESTS_SH = os.path.join(BASE_DIR, "run_tests.sh")
EXECUTABLE = os.path.join(BASE_DIR, "calcgraph")
EXPECTED = {
    "test1.cg": 25,
    "test2.cg": 42,
    "test3.cg": 95,
}


def run_checked(args, **kwargs):
    return subprocess.run(args, capture_output=True, text=True, timeout=30, **kwargs)


def assert_real_executable(path):
    assert os.path.isfile(path), "calcgraph executable was not created by make."
    assert os.access(path, os.X_OK), "calcgraph is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "calcgraph is not a compiled ELF executable."


def assert_calcgraph_outputs():
    for filename, expected in EXPECTED.items():
        path = os.path.join(BASE_DIR, "tests", filename)
        result = run_checked([EXECUTABLE, path], cwd=BASE_DIR)
        assert result.returncode == 0, (
            f"calcgraph failed for {filename}:\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert result.stdout == f"{expected}\n", (
            f"calcgraph output for {filename} was {result.stdout!r}, expected {expected!r}"
        )


def test_build_succeeds():
    """Ensure that running make succeeds, implying missing includes and Makefile are fixed."""
    subprocess.run(["make", "clean"], cwd=BASE_DIR, capture_output=True)
    result = subprocess.run(["make"], cwd=BASE_DIR, capture_output=True, text=True)
    assert result.returncode == 0, f"make failed with output:\n{result.stderr}\n{result.stdout}"
    assert os.path.isfile(EXECUTABLE), "calcgraph executable was not created by make."
    assert_real_executable(EXECUTABLE)
    assert_calcgraph_outputs()


def test_eval_c_fixed():
    """Ensure the logic bug in eval.c is fixed for OP_MUL."""
    eval_c_path = os.path.join(BASE_DIR, "eval.c")
    assert os.path.isfile(eval_c_path), f"File {eval_c_path} is missing."

    with open(eval_c_path, "r") as f:
        content = f.read()

    assert "left_val * right_val" in content or "*" in content.split("OP_MUL")[1].split("\n")[0], \
        "eval.c does not seem to use '*' for OP_MUL. The logic bug is not fixed."

    probe_source = r'''
#include <stdio.h>
#include <stdlib.h>
#include "graph.h"
#include "eval.h"

int main(int argc, char **argv) {
    if (argc != 4) return 2;
    int op_number = atoi(argv[1]);
    int a = atoi(argv[2]);
    int b = atoi(argv[3]);
    OpType op;
    if (op_number == 1) op = OP_ADD;
    else if (op_number == 2) op = OP_MUL;
    else if (op_number == 3) op = OP_SUB;
    else return 3;

    Node left = { .id = 2, .op = OP_VAL, .val = a, .left = NULL, .right = NULL };
    Node right = { .id = 3, .op = OP_VAL, .val = b, .left = NULL, .right = NULL };
    Node root = { .id = 1, .op = op, .val = 0, .left = &left, .right = &right };
    printf("%d\n", evaluate_graph(&root));
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        source = os.path.join(td, "probe.c")
        binary = os.path.join(td, "probe")
        with open(source, "w") as f:
            f.write(probe_source)
        build = run_checked([
            "gcc", "-Wall", "-Werror", "-I", BASE_DIR,
            source, os.path.join(BASE_DIR, "eval.c"), "-o", binary,
        ])
        assert build.returncode == 0, f"eval.c could not be compiled into a probe:\n{build.stderr}"

        operations = {
            1: lambda a, b: a + b,
            2: lambda a, b: a * b,
            3: lambda a, b: a - b,
        }
        for op_number, operation in operations.items():
            for _ in range(12):
                a = secrets.randbelow(2001) - 1000
                b = secrets.randbelow(2001) - 1000
                expected = operation(a, b)
                result = run_checked([binary, str(op_number), str(a), str(b)])
                assert result.returncode == 0, f"evaluator probe failed: {result.stderr}"
                assert result.stdout == f"{expected}\n", (
                    f"evaluator returned {result.stdout!r} for operation {op_number} "
                    f"with operands {a}, {b}; expected {expected}"
                )


def test_run_tests_sh_exists_and_executable():
    """Ensure run_tests.sh exists, is executable, rebuilds, and runs the interpreter."""
    assert os.path.isfile(RUN_TESTS_SH), f"Script {RUN_TESTS_SH} does not exist."
    assert os.access(RUN_TESTS_SH, os.X_OK), f"Script {RUN_TESTS_SH} is not executable."

    clean = run_checked(["make", "clean"], cwd=BASE_DIR)
    assert clean.returncode == 0, f"make clean failed:\n{clean.stderr}"
    if os.path.exists(RESULTS_LOG):
        os.unlink(RESULTS_LOG)
    assert not os.path.exists(EXECUTABLE), "make clean did not remove calcgraph before runner test."

    result = run_checked([RUN_TESTS_SH], cwd=BASE_DIR)
    assert result.returncode == 0, (
        f"run_tests.sh failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert_real_executable(EXECUTABLE)
    assert_calcgraph_outputs()


def test_results_log_matches_expected():
    """Ensure results.log exists and contains exactly the expected output."""
    assert os.path.isfile(RESULTS_LOG), f"{RESULTS_LOG} does not exist. Did the script run?"

    with open(RESULTS_LOG, "r") as f:
        lines = [line.strip() for line in f.read().strip().split("\n")]

    expected_lines = [
        "test1: 25",
        "test2: 42",
        "test3: 95"
    ]

    assert len(lines) == 3, f"{RESULTS_LOG} should contain exactly 3 lines, found {len(lines)}."
    for i, expected in enumerate(expected_lines):
        assert lines[i] == expected, f"Line {i+1} in {RESULTS_LOG} is '{lines[i]}', expected '{expected}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
