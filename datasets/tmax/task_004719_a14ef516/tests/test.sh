#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import ctypes
import json
import os
import random
import re
import signal
import string
import subprocess
import sys
import time

import pytest
import requests
import websockets

WORKSPACE_DIR = "/home/user/polyglot_auth"
BUILD_DIR = os.path.join(WORKSPACE_DIR, "build")
LIB_PATH = os.path.join(BUILD_DIR, "libsecure_hash.so")
SERVER_PATH = os.path.join(WORKSPACE_DIR, "src", "server.py")
E2E_PATH = os.path.join(WORKSPACE_DIR, "tests", "test_e2e.py")
LOG_PATH = os.path.join(WORKSPACE_DIR, "test_results.log")


def expected_hash(message):
    return "".join(f"{byte ^ 0x42:02x}" for byte in message.encode("utf-8"))


def stop_existing_servers():
    target = os.path.realpath(SERVER_PATH)
    victims = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            raw = open(f"/proc/{entry}/cmdline", "rb").read()
            args = [part.decode(errors="ignore") for part in raw.split(b"\0") if part]
        except (OSError, PermissionError):
            continue
        if any(os.path.realpath(arg) == target for arg in args if arg.startswith("/")):
            victims.append(int(entry))
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


@pytest.fixture(scope="session", autouse=True)
def build_project():
    assert os.path.isfile(os.path.join(WORKSPACE_DIR, "CMakeLists.txt"))
    if os.path.isdir(BUILD_DIR):
        subprocess.run(["rm", "-rf", BUILD_DIR], check=True)
    os.makedirs(BUILD_DIR)
    subprocess.run(
        ["cmake", ".."], cwd=BUILD_DIR, check=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30
    )
    subprocess.run(
        ["cmake", "--build", "."], cwd=BUILD_DIR, check=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30
    )
    assert os.path.isfile(LIB_PATH), f"CMake did not produce {LIB_PATH}"
    yield


@pytest.fixture(scope="session")
def running_server(build_project):
    assert os.path.isfile(SERVER_PATH), f"Missing backend: {SERVER_PATH}"
    stop_existing_servers()
    proc = subprocess.Popen(
        [sys.executable, SERVER_PATH], cwd=WORKSPACE_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        start_new_session=True
    )
    deadline = time.time() + 20
    last_error = None
    while time.time() < deadline:
        if proc.poll() is not None:
            output = proc.stdout.read() if proc.stdout else ""
            pytest.fail(f"server.py exited before becoming ready (code {proc.returncode}):\n{output}")
        try:
            response = requests.post(
                "http://127.0.0.1:5000/api/hash",
                json={"message": "verifier-ready"}, timeout=1
            )
            if response.status_code == 200 and response.json() == {
                "hash": expected_hash("verifier-ready")
            }:
                break
        except Exception as exc:
            last_error = exc
        time.sleep(0.2)
    else:
        proc.terminate()
        output = proc.communicate(timeout=3)[0]
        pytest.fail(f"Backend did not become ready: {last_error}\n{output}")

    try:
        yield proc
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
            proc.wait(timeout=3)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def test_cmake_fixed():
    """Keep the original assertion that CMake requests a shared library."""
    cmake_path = os.path.join(WORKSPACE_DIR, "CMakeLists.txt")
    assert os.path.isfile(cmake_path), f"{cmake_path} does not exist."
    content = open(cmake_path).read()
    assert "SHARED" in content, "CMakeLists.txt does not contain 'SHARED'."
    assert "STATIC" not in content, "CMakeLists.txt still contains 'STATIC'."


def test_c_source_fixed():
    """Keep the original source-level allocation assertions."""
    c_path = os.path.join(WORKSPACE_DIR, "lib", "secure_hash.c")
    assert os.path.isfile(c_path), f"{c_path} does not exist."
    content = open(c_path).read()
    assert not re.search(r'malloc\s*\(\s*len\s*\)', content), \
        "secure_hash.c still contains the buggy malloc(len)."
    assert re.search(r'(malloc|calloc)\s*\([^;]*len\s*\+\s*[1-9][0-9]*[^;]*\)', content), \
        "secure_hash.c does not safely allocate len + 1 (or more)."


def test_shared_library_loads_and_hashes(build_project):
    lib = ctypes.CDLL(LIB_PATH)
    compute_hash = lib.compute_hash
    compute_hash.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    compute_hash.restype = None

    samples = ["", "a", "HelloREST", "HelloWS", "0123456789", "x" * 4096]
    samples.append("verify-" + "".join(random.choice(string.ascii_letters) for _ in range(31)))
    for message in samples:
        raw = message.encode("utf-8")
        output = ctypes.create_string_buffer(len(raw) * 2 + 1)
        compute_hash(raw, output)
        assert output.value.decode("ascii") == expected_hash(message)


def test_c_implementation_under_address_sanitizer(build_project, tmp_path):
    harness = tmp_path / "hash_harness.c"
    executable = tmp_path / "hash_harness"
    harness.write_text(r'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "secure_hash.h"
int main(void) {
    size_t lengths[] = {0, 1, 9, 257, 4096};
    for (size_t k = 0; k < sizeof(lengths)/sizeof(lengths[0]); ++k) {
        size_t n = lengths[k];
        char *in = malloc(n + 1);
        char *out = calloc(n * 2 + 1, 1);
        if (!in || !out) return 2;
        for (size_t i = 0; i < n; ++i) in[i] = (char)('!' + (i % 90));
        in[n] = '\0';
        compute_hash(in, out);
        if (strlen(out) != n * 2) return 3;
        for (size_t i = 0; i < n; ++i) {
            char expected[3];
            snprintf(expected, sizeof(expected), "%02x", ((unsigned char)in[i]) ^ 0x42);
            if (out[i*2] != expected[0] || out[i*2+1] != expected[1]) return 4;
        }
        free(in); free(out);
    }
    return 0;
}
''')
    subprocess.run([
        "cc", "-fsanitize=address", "-fno-omit-frame-pointer", "-g",
        "-I", os.path.join(WORKSPACE_DIR, "lib"),
        str(harness), os.path.join(WORKSPACE_DIR, "lib", "secure_hash.c"),
        "-o", str(executable)
    ], check=True, timeout=30)
    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1"
    subprocess.run([str(executable)], check=True, env=env, timeout=30)


def test_rest_api_with_derived_inputs(running_server):
    messages = ["", "REST-" + os.urandom(12).hex(), "z" * 1024]
    for message in messages:
        response = requests.post(
            "http://127.0.0.1:5000/api/hash",
            json={"message": message}, timeout=5
        )
        assert response.status_code == 200
        assert response.headers.get("content-type", "").lower().startswith("application/json")
        assert response.json() == {"hash": expected_hash(message)}


def test_websocket_api_with_derived_inputs(running_server):
    async def exercise():
        async with websockets.connect("ws://127.0.0.1:8765", open_timeout=5) as ws:
            for message in ["", "WS-" + os.urandom(12).hex(), "q" * 1024]:
                await ws.send(message)
                raw = await asyncio.wait_for(ws.recv(), timeout=5)
                assert json.loads(raw) == {"hash": expected_hash(message)}
    asyncio.run(exercise())


def test_requested_e2e_client_and_results_log(running_server):
    assert os.path.isfile(E2E_PATH), f"Missing E2E client: {E2E_PATH}"
    try:
        os.remove(LOG_PATH)
    except FileNotFoundError:
        pass
    completed = subprocess.run(
        [sys.executable, E2E_PATH], cwd=WORKSPACE_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30
    )
    assert completed.returncode == 0, f"E2E client failed:\n{completed.stdout}"

    # Keep the original final-state assertion, but only after actually running the client.
    assert os.path.isfile(LOG_PATH), f"Test results log {LOG_PATH} does not exist."
    content = open(LOG_PATH).read().strip()
    assert content == "E2E_TESTS_PASSED", \
        f"Expected 'E2E_TESTS_PASSED' in test_results.log, but found: '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
