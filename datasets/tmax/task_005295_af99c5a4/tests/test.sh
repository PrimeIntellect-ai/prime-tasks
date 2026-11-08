#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import re
import secrets
import socket
import subprocess
import sys
import time
import urllib.parse
import urllib.request

import pytest

WORKSPACE_DIR = "/home/user/workspace"
RESOLUTION_FILE = os.path.join(WORKSPACE_DIR, "resolution.json")
RUST_DIR = os.path.join(WORKSPACE_DIR, "rust_lib")
RUST_SO = os.path.join(RUST_DIR, "target", "debug", "librustffi.so")
RUST_SRC = os.path.join(RUST_DIR, "src", "lib.rs")
PYTHON_API_DIR = os.path.join(WORKSPACE_DIR, "python_api")
AUDIT_DIR = "/tmp/dataproc_audit"
AUDIT_SO = os.path.join(AUDIT_DIR, "libdataproc.so")


def clean_env():
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    env.pop("LD_PRELOAD", None)
    return env


@pytest.fixture(scope="session", autouse=True)
def build_and_prepare():
    subprocess.run(["cargo", "clean"], cwd=RUST_DIR, env=clean_env(), check=True)
    result = subprocess.run(
        ["cargo", "build"], cwd=RUST_DIR, env=clean_env(),
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    assert result.returncode == 0, f"Rust library did not compile from the submitted source:\n{result.stdout}"

    os.makedirs(AUDIT_DIR, exist_ok=True)
    audit_c = os.path.join(AUDIT_DIR, "audit.c")
    with open(audit_c, "w") as f:
        f.write(r'''
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct { uint64_t magic; } header;
static const uint64_t MAGIC = UINT64_C(0x91ad5e77c0ffee42);
static int process_calls = 0;
static int valid_free_calls = 0;
static int invalid_free_calls = 0;

char *process_text(const char *input) {
    if (!input) return NULL;
    const char *prefix = "AUDIT:";
    size_t n = strlen(prefix) + strlen(input) + 1;
    header *h = malloc(sizeof(header) + n);
    if (!h) return NULL;
    h->magic = MAGIC;
    char *out = (char *)(h + 1);
    strcpy(out, prefix);
    strcat(out, input);
    process_calls++;
    return out;
}

void free_text(char *ptr) {
    if (!ptr) { invalid_free_calls++; return; }
    header *h = ((header *)ptr) - 1;
    if (h->magic != MAGIC) { invalid_free_calls++; return; }
    h->magic = 0;
    valid_free_calls++;
    free(h);
}

int audit_process_calls(void) { return process_calls; }
int audit_valid_free_calls(void) { return valid_free_calls; }
int audit_invalid_free_calls(void) { return invalid_free_calls; }
''')
    subprocess.run(
        ["gcc", "-shared", "-fPIC", "-Wl,-soname,libdataproc.so", "-o", AUDIT_SO, audit_c],
        check=True
    )


def test_resolution_json_exists_and_valid():
    assert os.path.exists(RESOLUTION_FILE), "resolution.json not found at expected path."
    with open(RESOLUTION_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("resolution.json is not valid JSON.")

    expected_keys = {"rust_compile_fix", "memory_leak_fix", "linking_fix"}
    assert expected_keys.issubset(data.keys()), f"resolution.json missing keys. Expected to contain: {expected_keys}"
    for key in expected_keys:
        assert isinstance(data[key], str), f"resolution.json field {key} must be a string."


def test_rust_library_compiled():
    assert os.path.exists(RUST_SO), f"Rust library not found at {RUST_SO}. Did you compile it?"
    assert os.path.getsize(RUST_SO) > 0, "Rust library is empty."

    dynamic = subprocess.run(
        ["readelf", "-d", RUST_SO], check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    ).stdout
    assert re.search(r"Shared library: \[libdataproc\.so\]", dynamic), \
        "librustffi.so is not dynamically linked to the required C library libdataproc.so."


# Retain the original source assertions and additionally ensure comments cannot satisfy them.
def test_rust_code_fixes():
    assert os.path.exists(RUST_SRC), f"Rust source file not found at {RUST_SRC}"
    with open(RUST_SRC, "r") as f:
        code = f.read()

    assert "free_text(" in code, "Verification failed: Memory leak not fixed (missing free_text call in Rust code)."
    assert ".into_raw()" in code or "CString::into_raw" in code, "Verification failed: Rust compile fix doesn't use into_raw(), might still return dangling pointer."

    uncommented = re.sub(r"/\*.*?\*/", "", code, flags=re.S)
    uncommented = re.sub(r"//.*", "", uncommented)
    assert ".into_raw()" in uncommented or "CString::into_raw" in uncommented, \
        "into_raw only appears in comments, not in the submitted Rust implementation."


def test_rust_ffi_uses_c_and_frees_each_c_allocation():
    values = ["ffi_" + secrets.token_hex(10) for _ in range(7)]
    child = r'''
import ctypes, json, sys
rust_path, audit_path, values_json = sys.argv[1:]
values = json.loads(values_json)
audit = ctypes.CDLL(audit_path, mode=ctypes.RTLD_GLOBAL)
rust = ctypes.CDLL(rust_path)
rust.process_via_rust.argtypes = [ctypes.c_char_p]
rust.process_via_rust.restype = ctypes.c_void_p
rust.free_rust_string.argtypes = [ctypes.c_void_p]
rust.free_rust_string.restype = None
for value in values:
    ptr = rust.process_via_rust(value.encode())
    assert ptr, "process_via_rust returned NULL"
    result = ctypes.string_at(ptr).decode()
    assert result == "AUDIT:" + value + "_RUSTIFIED", (value, result)
    rust.free_rust_string(ptr)
audit.audit_process_calls.restype = ctypes.c_int
audit.audit_valid_free_calls.restype = ctypes.c_int
audit.audit_invalid_free_calls.restype = ctypes.c_int
assert audit.audit_process_calls() == len(values), audit.audit_process_calls()
assert audit.audit_valid_free_calls() == len(values), audit.audit_valid_free_calls()
assert audit.audit_invalid_free_calls() == 0, audit.audit_invalid_free_calls()
'''
    env = clean_env()
    env["LD_PRELOAD"] = AUDIT_SO
    env["LD_LIBRARY_PATH"] = AUDIT_DIR
    result = subprocess.run(
        [sys.executable, "-c", child, RUST_SO, AUDIT_SO, json.dumps(values)],
        env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    assert result.returncode == 0, f"Rust FFI behavioral/memory test failed:\n{result.stdout}"


def unused_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def request_json(url):
    with urllib.request.urlopen(url, timeout=3) as response:
        assert response.status == 200, f"Expected status 200, got {response.status}"
        return json.loads(response.read().decode())


def start_server(env):
    port = unused_port()
    proc = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "app:app", "--host", "127.0.0.1", "--port", str(port)],
        cwd=PYTHON_API_DIR, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        text=True
    )
    deadline = time.time() + 10
    while time.time() < deadline:
        if proc.poll() is not None:
            stderr = proc.stderr.read()
            pytest.fail(f"FastAPI server crashed or failed to start. Check linking or syntax errors.\n{stderr}")
        try:
            request_json(f"http://127.0.0.1:{port}/stats")
            return proc, port
        except Exception:
            time.sleep(0.1)
    proc.terminate()
    proc.wait(timeout=5)
    pytest.fail("FastAPI server did not become ready.")


def stop_server(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)


def test_python_api_endpoints_and_persistent_linking():
    # No verifier-supplied loader path: the submitted persistent linking fix must work itself.
    proc, port = start_server(clean_env())
    try:
        assert request_json(f"http://127.0.0.1:{port}/stats") == {"status": "ok", "processed_count": 0}
        values = ["api_" + secrets.token_hex(8) for _ in range(4)]
        for index, value in enumerate(values, 1):
            query = urllib.parse.urlencode({"text": value})
            data = request_json(f"http://127.0.0.1:{port}/process?{query}")
            assert data == {"result": "PROCESSED:" + value + "_RUSTIFIED"}
            assert request_json(f"http://127.0.0.1:{port}/stats") == {
                "status": "ok", "processed_count": index
            }
    finally:
        stop_server(proc)


def test_python_api_really_calls_native_ffi():
    # Interpose a verifier-derived C implementation. A hardcoded Python response cannot predict its prefix.
    env = clean_env()
    env["LD_PRELOAD"] = AUDIT_SO
    proc, port = start_server(env)
    try:
        value = "interposed_" + secrets.token_hex(12)
        query = urllib.parse.urlencode({"text": value})
        data = request_json(f"http://127.0.0.1:{port}/process?{query}")
        assert data == {"result": "AUDIT:" + value + "_RUSTIFIED"}
        assert request_json(f"http://127.0.0.1:{port}/stats") == {
            "status": "ok", "processed_count": 1
        }
    finally:
        stop_server(proc)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
