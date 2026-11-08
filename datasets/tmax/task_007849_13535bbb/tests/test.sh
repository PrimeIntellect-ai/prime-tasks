#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import tempfile

import pytest

PROJECT_DIR = "/home/user/websec_project"
LIB_DIR = os.path.join(PROJECT_DIR, "lib")


def test_directories_exist():
    """Verify that the required directories have been created."""
    expected_dirs = ["src", "include", "lib", "tests"]
    for d in expected_dirs:
        dir_path = os.path.join(PROJECT_DIR, d)
        assert os.path.isdir(dir_path), f"Expected directory {dir_path} does not exist."


def test_file_relocations():
    """Verify that the source files were moved to their correct directories."""
    checksum_c = os.path.join(PROJECT_DIR, "src", "checksum.c")
    checksum_h = os.path.join(PROJECT_DIR, "include", "checksum.h")

    assert os.path.isfile(checksum_c), f"File {checksum_c} is missing. Was it moved?"
    assert os.path.isfile(checksum_h), f"File {checksum_h} is missing. Was it moved?"

    assert not os.path.exists(os.path.join(PROJECT_DIR, "checksum.c")), "checksum.c should not be in the project root."
    assert not os.path.exists(os.path.join(PROJECT_DIR, "checksum.h")), "checksum.h should not be in the project root."


def test_shared_library_abi():
    """Verify the shared library exists and has the correct exported/hidden symbols."""
    lib_path = os.path.join(LIB_DIR, "libwebsec.so")
    assert os.path.isfile(lib_path), f"Shared library {lib_path} does not exist."

    result = subprocess.run(["nm", "-D", lib_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to run nm on {lib_path}. Is it a valid shared object?"

    output = result.stdout
    assert "generate_web_token_hash" in output, "Symbol 'generate_web_token_hash' is missing from the dynamic symbol table."
    assert "internal_mix_entropy" not in output, "Symbol 'internal_mix_entropy' is exported in the dynamic symbol table, but it MUST be hidden."


def test_hash_implementation_on_derived_inputs():
    """Load the submitted library and compare it with independently derived DJB2 results."""
    lib_path = os.path.join(LIB_DIR, "libwebsec.so")
    alphabet = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    vectors = [b"", b"abcde", b"WebToken123", b"Z" * 20]
    for length in range(5, 21):
        raw = os.urandom(length)
        vectors.append(bytes(alphabet[b % len(alphabet)] for b in raw))

    encoded = [v.hex() for v in vectors]
    helper = r'''
import ctypes, json, os, sys
lib = ctypes.CDLL(os.environ["WEBSEC_LIBRARY"])
fn = lib.generate_web_token_hash
fn.argtypes = [ctypes.c_char_p]
fn.restype = ctypes.c_uint
for item in json.loads(os.environ["WEBSEC_VECTORS"]):
    data = bytes.fromhex(item)
    expected = 5381
    for c in data:
        expected = ((expected << 5) + expected + c) & 0xffffffff
    actual = int(fn(data))
    if actual != expected:
        print(f"wrong hash for {data!r}: expected {expected}, got {actual}", file=sys.stderr)
        sys.exit(1)
'''
    env = os.environ.copy()
    env["WEBSEC_LIBRARY"] = lib_path
    env["WEBSEC_VECTORS"] = json.dumps(encoded)
    result = subprocess.run(["python3", "-c", helper], env=env, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr or "The shared library failed a functional hash test."


@pytest.fixture(scope="session")
def audit_library():
    """Build an interposer that observes calls made by the property test."""
    source = r'''
#define _GNU_SOURCE
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned int calls = 0;
static int valid = 1;
static int varied = 0;
static char pending[32];
static char first_string[32];

unsigned int generate_web_token_hash(const char *input) {
    const char *mode = getenv("WEBSEC_AUDIT_MODE");
    size_t len;
    unsigned int result;

    if (!input) {
        valid = 0;
        return 1;
    }

    len = strnlen(input, 21);
    if (len < 5 || len > 20)
        valid = 0;
    for (size_t i = 0; i < len && i <= 20; ++i) {
        if (!isalnum((unsigned char)input[i]))
            valid = 0;
    }

    if ((calls % 2) == 0) {
        if (calls == 0) {
            snprintf(first_string, sizeof(first_string), "%s", input);
        } else if (strcmp(first_string, input) != 0) {
            varied = 1;
        }
        snprintf(pending, sizeof(pending), "%s", input);
    } else if (strcmp(pending, input) != 0) {
        valid = 0;
    }

    calls++;
    if (mode && strcmp(mode, "zero") == 0)
        return 0;
    if (mode && strcmp(mode, "nondeterministic") == 0)
        return calls;

    result = 5381;
    for (size_t i = 0; i < len; ++i)
        result = result * 33u + (unsigned char)input[i];
    return result ? result : 1;
}

__attribute__((destructor)) static void finish_audit(void) {
    const char *mode = getenv("WEBSEC_AUDIT_MODE");
    const char *marker = getenv("WEBSEC_AUDIT_MARKER");
    if (mode && strcmp(mode, "valid") == 0 && marker &&
        calls == 200 && valid && varied) {
        FILE *f = fopen(marker, "w");
        if (f) {
            fputs("ok", f);
            fclose(f);
        }
    }
}
'''
    src = "/tmp/websec_audit.c"
    so = "/tmp/websec_audit.so"
    with open(src, "w") as f:
        f.write(source)
    result = subprocess.run(["gcc", "-shared", "-fPIC", src, "-o", so], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    return so


def assert_linked_to_library(executable):
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = LIB_DIR + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    result = subprocess.run(["ldd", executable], env=env, capture_output=True, text=True)
    assert result.returncode == 0, f"ldd failed for {executable}: {result.stderr}"
    output = result.stdout + result.stderr
    assert "libwebsec.so" in output, f"{executable} is not dynamically linked against libwebsec.so."
    assert "not found" not in output, f"A required shared library for {executable} was not found: {output}"


def exercise_property_test(executable, audit_library):
    assert_linked_to_library(executable)
    marker = tempfile.mktemp(prefix="websec_audit_")
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = LIB_DIR + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    env["LD_PRELOAD"] = audit_library
    env["WEBSEC_AUDIT_MARKER"] = marker

    env["WEBSEC_AUDIT_MODE"] = "valid"
    result = subprocess.run([executable], env=env, capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, f"Property test failed on valid hashes: {result.stderr}"
    assert result.stdout.strip() == "PROPERTY_TEST_SUCCESS", "Property test did not print PROPERTY_TEST_SUCCESS."
    assert os.path.isfile(marker), "Property test did not make exactly 100 paired calls using varied alphanumeric strings of lengths 5-20."
    os.unlink(marker)

    env["WEBSEC_AUDIT_MODE"] = "zero"
    result = subprocess.run([executable], env=env, capture_output=True, text=True, timeout=15)
    assert result.returncode != 0, "Property test did not fail when the hash returned zero."

    env["WEBSEC_AUDIT_MODE"] = "nondeterministic"
    result = subprocess.run([executable], env=env, capture_output=True, text=True, timeout=15)
    assert result.returncode != 0, "Property test did not fail when repeated hashes were non-deterministic."


def test_executable_source_and_log(audit_library):
    """Verify, execute, and instrument both the submitted test executable and source."""
    source_path = os.path.join(PROJECT_DIR, "tests", "prop_test.c")
    exe_path = os.path.join(PROJECT_DIR, "tests", "prop_test")
    log_path = os.path.join(PROJECT_DIR, "test_result.log")

    assert os.path.isfile(source_path), f"Property-test source {source_path} does not exist."
    assert os.path.isfile(exe_path), f"Test executable {exe_path} does not exist."
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "PROPERTY_TEST_SUCCESS", f"Log file content is incorrect. Expected 'PROPERTY_TEST_SUCCESS', got '{content}'."

    run_env = os.environ.copy()
    run_env["LD_LIBRARY_PATH"] = LIB_DIR + (":" + run_env["LD_LIBRARY_PATH"] if run_env.get("LD_LIBRARY_PATH") else "")
    direct = subprocess.run([exe_path], env=run_env, capture_output=True, text=True, timeout=15)
    assert direct.returncode == 0, f"Submitted property-test executable failed: {direct.stderr}"
    assert direct.stdout.strip() == "PROPERTY_TEST_SUCCESS", "Submitted executable produced incorrect output."
    exercise_property_test(exe_path, audit_library)

    rebuilt = "/tmp/rebuilt_prop_test"
    compile_result = subprocess.run([
        "gcc", source_path,
        "-I", os.path.join(PROJECT_DIR, "include"),
        "-L", LIB_DIR,
        "-lwebsec",
        "-Wl,-rpath," + LIB_DIR,
        "-o", rebuilt,
    ], capture_output=True, text=True)
    assert compile_result.returncode == 0, f"prop_test.c could not be compiled against libwebsec.so: {compile_result.stderr}"
    exercise_property_test(rebuilt, audit_library)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
