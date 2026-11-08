#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile

import pytest

ROOT = "/home/user/py_ext"
C_FILE = os.path.join(ROOT, "fast_req.c")


def run(cmd, **kwargs):
    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1:abort_on_error=1"
    return subprocess.run(cmd, env=env, text=True, capture_output=True,
                          timeout=30, **kwargs)


def test_success_log_exists_and_correct():
    log_path = "/home/user/py_ext/success.log"
    assert os.path.isfile(log_path), f"Success log file {log_path} is missing. Did you run the tests and redirect the output?"

    with open(log_path, "r") as f:
        content = f.read()

    assert content.strip() == "ALL TESTS PASSED", f"Expected success.log to contain exactly 'ALL TESTS PASSED', but got: {content}"


def test_fast_req_conditional_compilation():
    c_file_path = "/home/user/py_ext/fast_req.c"
    assert os.path.isfile(c_file_path), f"File {c_file_path} is missing."

    with open(c_file_path, "r") as f:
        content = f.read()

    assert "#if PY_MAJOR_VERSION >= 3" in content, "Missing '#if PY_MAJOR_VERSION >= 3' macro in fast_req.c"
    assert "PyUnicode_AsUTF8" in content, "Missing 'PyUnicode_AsUTF8' call for Python 3 logic in fast_req.c"
    assert "PyString_AsString" in content, "Missing 'PyString_AsString' call for Python 2 logic in fast_req.c"


def test_fast_req_memory_safety():
    c_file_path = "/home/user/py_ext/fast_req.c"
    assert os.path.isfile(c_file_path), f"File {c_file_path} is missing."

    with open(c_file_path, "r") as f:
        content = f.read()

    assert re.search(r"malloc\s*\(\s*len\s*\+\s*1\s*\)", content), "Off-by-one error not fixed: could not find malloc(len + 1) in fast_req.c"
    assert re.search(r"free\s*\(\s*buffer\s*\)", content), "Memory leak not fixed: could not find free(buffer) in error path of fast_req.c"


def test_migration_patch_exists_and_valid():
    patch_path = "/home/user/py_ext/migration.patch"
    assert os.path.isfile(patch_path), f"Patch file {patch_path} is missing."

    with open(patch_path, "r") as f:
        content = f.read()

    assert content.startswith("--- "), "Patch file does not appear to be a valid unified diff (should start with '--- ')."
    assert "\n+++ " in content, "Patch file does not appear to be a valid unified diff (missing '+++ ')."
    assert "fast_req.c" in content, "Patch file doesn't seem to reference fast_req.c."

    original = os.path.join(ROOT, "fast_req.c.orig")
    assert os.path.isfile(original), "fast_req.c.orig is missing"
    with tempfile.TemporaryDirectory() as td:
        result = os.path.join(td, "patched.c")
        proc = run(["patch", "--batch", "--silent", "-o", result,
                    original, "-i", patch_path])
        assert proc.returncode == 0, f"migration.patch does not apply to fast_req.c.orig:\n{proc.stdout}{proc.stderr}"
        with open(result, "rb") as f:
            patched = f.read()
        with open(C_FILE, "rb") as f:
            current = f.read()
        assert patched == current, "migration.patch does not reproduce the submitted fast_req.c from fast_req.c.orig"


def test_provided_build_and_test_executable_really_passes():
    clean = run(["make", "clean"], cwd=ROOT)
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout}{clean.stderr}"
    build = run(["make"], cwd=ROOT)
    assert build.returncode == 0, f"Makefile build failed:\n{build.stdout}{build.stderr}"

    executable = os.path.join(ROOT, "test_ext")
    assert os.path.isfile(executable) and os.access(executable, os.X_OK), "Makefile did not produce an executable test_ext"
    result = run([executable], cwd=ROOT)
    assert result.returncode == 0, f"test_ext failed:\n{result.stdout}{result.stderr}"
    assert result.stdout == "ALL TESTS PASSED\n", f"Unexpected test_ext output: {result.stdout!r}"
    assert result.stderr == "", f"test_ext emitted errors or sanitizer diagnostics:\n{result.stderr}"

    with open(os.path.join(ROOT, "success.log"), "rb") as f:
        logged = f.read()
    assert logged == result.stdout.encode(), "success.log is not the exact output produced by test_ext"


HARNESS = r'''
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "python_mock.h"

char *parse_header(const char *input);
char *extract_string(PyObject *obj);
int check_rate_limit(uint32_t client_id, uint64_t current_time_ms);

#define CHECK(expr) do { \
    if (!(expr)) { \
        fprintf(stderr, "hidden check failed at line %d: %s\n", __LINE__, #expr); \
        return 1; \
    } \
} while (0)

int main(void) {
    CHECK(parse_header(NULL) == NULL);

    char *empty = parse_header("");
    CHECK(empty != NULL);
    CHECK(strcmp(empty, "") == 0);
    free(empty);

    char edge[102];
    memset(edge, 'x', 101);
    edge[100] = '\0';
    char *accepted = parse_header(edge);
    CHECK(accepted != NULL);
    CHECK(strlen(accepted) == 100);
    CHECK(strcmp(accepted, edge) == 0);
    free(accepted);

    edge[100] = 'x';
    edge[101] = '\0';
    CHECK(parse_header(edge) == NULL);

    PyObject obj;
    obj.data = "conditional-string";
    CHECK(strcmp(extract_string(&obj), "conditional-string") == 0);

    CHECK(check_rate_limit(100, 1000) == 0);
    CHECK(check_rate_limit(UINT32_MAX, 1000) == 0);

    for (int i = 0; i < 10; ++i)
        CHECK(check_rate_limit(17, 1000) == 1);
    CHECK(check_rate_limit(17, 1000) == 0);

    for (int i = 0; i < 3; ++i)
        CHECK(check_rate_limit(17, 1300) == 1);
    CHECK(check_rate_limit(17, 1300) == 0);

    /* Buckets must be independent for different client IDs. */
    for (int i = 0; i < 10; ++i)
        CHECK(check_rate_limit(18, 1300) == 1);
    CHECK(check_rate_limit(18, 1300) == 0);

    /* A long wait refills only to the capacity of ten. */
    for (int i = 0; i < 10; ++i)
        CHECK(check_rate_limit(17, 11300) == 1);
    CHECK(check_rate_limit(17, 11300) == 0);

    puts("HIDDEN TESTS PASSED");
    return 0;
}
'''


@pytest.mark.parametrize("major", [2, 3])
def test_hidden_functional_harness(major):
    with tempfile.TemporaryDirectory() as td:
        harness = os.path.join(td, "functional_test.c")
        executable = os.path.join(td, f"functional_test_py{major}")
        with open(harness, "w") as f:
            f.write(HARNESS)

        compile_result = run([
            "gcc", "-std=c11", "-g", "-Wall", "-fsanitize=address",
            f"-DPY_MAJOR_VERSION={major}", "-I", ROOT,
            C_FILE, harness, "-o", executable,
        ])
        assert compile_result.returncode == 0, (
            f"fast_req.c failed to compile for PY_MAJOR_VERSION={major}:\n"
            f"{compile_result.stdout}{compile_result.stderr}"
        )

        result = run([executable])
        assert result.returncode == 0, (
            f"Functional or sanitizer tests failed for PY_MAJOR_VERSION={major}:\n"
            f"{result.stdout}{result.stderr}"
        )
        assert result.stdout == "HIDDEN TESTS PASSED\n"
        assert result.stderr == ""
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
