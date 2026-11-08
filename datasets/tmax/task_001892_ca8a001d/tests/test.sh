#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile

CPP = "/home/user/process_queries.cpp"
BINARY = "/home/user/process_queries"
QUERIES = "/home/user/queries.txt"
RESULT = "/home/user/debug_result.txt"


def test_debug_result_content():
    path = RESULT
    assert os.path.isfile(path), f"Verification failed: {path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip()

    expected = "ID: 3412, CORRECT_HASH: 15"
    assert content == expected, f"Verification failed. Expected '{expected}', got '{content}'."


def test_cpp_file_exists():
    path = CPP
    assert os.path.isfile(path), f"Verification failed: {path} does not exist."


def test_recompiled_binary_exists():
    assert os.path.isfile(BINARY), f"Verification failed: {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"Verification failed: {BINARY} is not executable."


def test_fixed_formula_and_program_execution():
    with open(QUERIES, "r") as f:
        rows = [line.split() for line in f if line.strip()]

    failing = [row for row in rows if len(row) == 3 and row[0] == "3412"]
    assert len(failing) == 1, "queries.txt must contain exactly one query with ID 3412."
    query_id, x_text, y_text = failing[0]
    x = int(x_text)
    int(y_text)
    expected_hash = ((x * 73) % 100 + 100) % 100

    with open(RESULT, "r") as f:
        actual_result = f.read().strip()
    assert actual_result == f"ID: {query_id}, CORRECT_HASH: {expected_hash}"

    with tempfile.TemporaryDirectory() as td:
        single_query = os.path.join(td, "single_query.txt")
        with open(single_query, "w") as f:
            f.write(" ".join(failing[0]) + "\n")

        fresh_binary = os.path.join(td, "process_queries")
        compile_result = subprocess.run(
            ["g++", "-std=c++17", CPP, "-o", fresh_binary],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert compile_result.returncode == 0, compile_result.stderr

        harness_source = os.path.join(td, "formula_harness.cpp")
        harness_binary = os.path.join(td, "formula_harness")
        with open(harness_source, "w") as f:
            f.write(r'''
#define main submission_program_main
#include "/home/user/process_queries.cpp"
#undef main
#include <iostream>

int main() {
    for (int x = -10000; x <= 10000; ++x) {
        int expected = static_cast<int>(((static_cast<long long>(x) * 73) % 100 + 100) % 100);
        int actual = compute_hash_index(x);
        if (actual < 0 || actual > 99 || actual != expected) {
            std::cerr << "Incorrect hash for x=" << x
                      << ": expected " << expected << ", got " << actual << std::endl;
            return 2;
        }
    }
    return 0;
}
''')

        harness_compile = subprocess.run(
            ["g++", "-std=c++17", harness_source, "-o", harness_binary],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert harness_compile.returncode == 0, harness_compile.stderr

        harness_run = subprocess.run(
            [harness_binary],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert harness_run.returncode == 0, harness_run.stderr

        for executable in (BINARY, fresh_binary):
            for input_path in (single_query, QUERIES):
                run = subprocess.run(
                    [executable, input_path],
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=30,
                )
                assert run.returncode == 0, (
                    f"{executable} failed on {input_path}:\n{run.stderr}"
                )
                assert "Processing complete." in run.stdout, (
                    f"{executable} did not complete processing for {input_path}."
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
