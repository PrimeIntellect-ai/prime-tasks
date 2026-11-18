#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess

WORKSPACE_DIR = "/home/user/workspace/librest_parser"
EXPECTED_OUTPUT = "TEST 1: PASS\nTEST 2: PASS\nTEST 3: PASS"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=30, **kwargs)


def test_make_succeeds():
    subprocess.run(["make", "clean"], cwd=WORKSPACE_DIR, capture_output=True)
    result = run(["make"], cwd=WORKSPACE_DIR)
    assert result.returncode == 0, f"make failed with output:\n{result.stderr}\n{result.stdout}"

    so_path = os.path.join(WORKSPACE_DIR, "librest_parser.so")
    assert os.path.isfile(so_path), f"Expected shared library {so_path} to be built."


def test_linking_issue_fixed():
    header_path = os.path.join(WORKSPACE_DIR, "include", "string_buf.h")
    assert os.path.isfile(header_path), f"Header file missing: {header_path}"

    with open(header_path, "r") as f:
        content = f.read()

    for line in content.split('\n'):
        if "global_alloc_count" in line and not line.strip().startswith("//"):
            if "int global_alloc_count" in line:
                assert "extern" in line, "global_alloc_count must be declared as extern in the header to fix the linking error."


def test_memory_leak_fixed():
    source_path = os.path.join(WORKSPACE_DIR, "src", "string_buf.c")
    assert os.path.isfile(source_path), f"Source file missing: {source_path}"

    with open(source_path, "r") as f:
        content = f.read()

    assert "free(buf)" in content.replace("free(buf->data)", ""), "The memory leak is not fixed. Missing free(buf) in string_buf.c."


def test_parser_behavior_and_memory_safety():
    harness_source = r'''#include "parser.h"
#include <stdio.h>

static int check_request(const char *input, int should_succeed) {
    rest_request_t *req = rest_request_new();
    if (req == NULL) {
        return 1;
    }

    int rc = parse_rest_request(input, req);
    rest_request_free(req);

    if (should_succeed) {
        return rc != 0;
    }
    return rc == 0;
}

int main(void) {
    int failed = 0;
    failed |= check_request("GET /api/v1/users HTTP/1.1\r\nHost: localhost\r\n\r\n", 1);
    failed |= check_request("INVALID / HTTP/1.1\r\n\r\n", 0);
    failed |= check_request("POST / HTTP/1.1\r\nHost localhost\r\n\r\n", 0);
    if (failed) {
        fprintf(stderr, "parser returned an incorrect result for a required input\n");
        return 2;
    }
    return 0;
}
'''
    harness_c = "/tmp/parser_verifier_harness.c"
    harness_exe = "/tmp/parser_verifier_harness"
    with open(harness_c, "w") as f:
        f.write(harness_source)

    compile_result = run([
        "gcc", "-Wall", "-Wextra", "-g", "-Iinclude",
        harness_c, "-L.", "-lrest_parser", "-Wl,-rpath," + WORKSPACE_DIR,
        "-o", harness_exe
    ], cwd=WORKSPACE_DIR)
    assert compile_result.returncode == 0, f"Could not compile parser verification harness:\n{compile_result.stderr}"

    result = run([harness_exe], cwd=WORKSPACE_DIR)
    assert result.returncode == 0, f"Parser failed required behavioral checks:\n{result.stdout}\n{result.stderr}"

    vg = run([
        "valgrind", "--leak-check=full", "--show-leak-kinds=all",
        "--errors-for-leak-kinds=all", "--error-exitcode=1", harness_exe
    ], cwd=WORKSPACE_DIR)
    assert vg.returncode == 0, f"Valgrind reported errors while parsing the required inputs:\n{vg.stderr}"
    assert "ERROR SUMMARY: 0 errors" in vg.stderr, f"Valgrind reported errors:\n{vg.stderr}"


def test_run_tests_executable_exists():
    test_source = os.path.join(WORKSPACE_DIR, "tests", "test_parser.c")
    assert os.path.isfile(test_source), f"Unit test file missing: {test_source}"

    run_tests_path = os.path.join(WORKSPACE_DIR, "run_tests")
    compile_result = run([
        "gcc", "-Wall", "-g", "-Iinclude", "tests/test_parser.c",
        "-L.", "-lrest_parser", "-Wl,-rpath," + WORKSPACE_DIR,
        "-o", "run_tests"
    ], cwd=WORKSPACE_DIR)
    assert compile_result.returncode == 0, f"Could not compile tests/test_parser.c:\n{compile_result.stderr}"
    assert os.path.isfile(run_tests_path), f"Executable missing: {run_tests_path}"
    assert os.access(run_tests_path, os.X_OK), f"File is not executable: {run_tests_path}"

    result = run(["./run_tests"], cwd=WORKSPACE_DIR)
    assert result.returncode == 0, f"run_tests failed:\n{result.stdout}\n{result.stderr}"
    assert result.stdout.strip() == EXPECTED_OUTPUT, f"run_tests produced unexpected output:\n{result.stdout}"

    log_path = os.path.join(WORKSPACE_DIR, "test_results.log")
    with open(log_path, "w") as f:
        f.write(result.stdout)


def test_test_results_log():
    log_path = os.path.join(WORKSPACE_DIR, "test_results.log")
    assert os.path.isfile(log_path), f"Log file missing: {log_path}"

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert EXPECTED_OUTPUT in content, f"Log file does not contain the expected output. Found:\n{content}"
    assert content == EXPECTED_OUTPUT, f"Log file must contain exactly the required lines. Found:\n{content}"


def test_valgrind_clean():
    run_tests_path = os.path.join(WORKSPACE_DIR, "run_tests")
    assert os.path.isfile(run_tests_path), "run_tests executable not found for valgrind check."

    result = run(
        ["valgrind", "--leak-check=full", "--error-exitcode=1", "./run_tests"],
        cwd=WORKSPACE_DIR
    )

    assert ("definitely lost: 0 bytes" in result.stderr or
            "All heap blocks were freed -- no leaks are possible" in result.stderr), \
        f"Valgrind reported memory leaks:\n{result.stderr}"
    assert result.returncode == 0, f"Valgrind reported errors:\n{result.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
