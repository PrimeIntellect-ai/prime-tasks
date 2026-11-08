#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import json
import os
import random
import shutil
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request

import pytest

WORKSPACE_DIR = "/home/user/mobile_pipeline"
LIB_PATH = os.path.join(WORKSPACE_DIR, "libsemver.so")
C_PATH = os.path.join(WORKSPACE_DIR, "semver.c")
MAKEFILE_PATH = os.path.join(WORKSPACE_DIR, "Makefile")
API_PATH = os.path.join(WORKSPACE_DIR, "resolver_api.py")
LOG_PATH = os.path.join(WORKSPACE_DIR, "pipeline.log")
API_URL = "http://127.0.0.1:8080/resolve"
READY_MESSAGE = "[API READY] Server listening on port 8080"
SERVER = None


def stop_servers():
    global SERVER
    if SERVER is not None and SERVER.poll() is None:
        try:
            os.killpg(SERVER.pid, signal.SIGTERM)
            SERVER.wait(timeout=3)
        except Exception:
            try:
                os.killpg(SERVER.pid, signal.SIGKILL)
            except Exception:
                pass
    SERVER = None
    subprocess.run(
        ["pkill", "-f", "[r]esolver_api.py"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    time.sleep(0.3)


def post_versions(versions, timeout=5):
    data = json.dumps({"versions": versions}).encode("utf-8")
    req = urllib.request.Request(
        API_URL,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        body = response.read().decode("utf-8")
        return response.status, json.loads(body)


def start_server(clear_log=True):
    global SERVER
    stop_servers()
    if clear_log:
        with open(LOG_PATH, "w", encoding="utf-8"):
            pass
    SERVER = subprocess.Popen(
        [sys.executable, API_PATH],
        cwd=WORKSPACE_DIR,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 8
    last_error = None
    while time.time() < deadline:
        if SERVER.poll() is not None:
            pytest.fail(f"resolver_api.py exited early with status {SERVER.returncode}")
        try:
            status, _ = post_versions(["0.0.1"])
            if status == 200:
                return
        except Exception as exc:
            last_error = exc
        time.sleep(0.15)
    pytest.fail(f"Submitted API did not become ready on 127.0.0.1:8080: {last_error}")


def expected_latest(versions):
    return max(versions, key=lambda value: tuple(int(part) for part in value.split(".")))


@pytest.fixture(scope="session", autouse=True)
def build_and_start_submission():
    assert os.path.isdir(WORKSPACE_DIR), f"Workspace directory missing: {WORKSPACE_DIR}"
    assert os.path.isfile(C_PATH), f"C source missing: {C_PATH}"
    assert os.path.isfile(MAKEFILE_PATH), f"Makefile missing: {MAKEFILE_PATH}"
    assert os.path.isfile(API_PATH), f"API script missing: {API_PATH}"

    with open(MAKEFILE_PATH, "r", encoding="utf-8", errors="replace") as handle:
        makefile = handle.read()
    assert "-O3" in makefile, "Makefile does not use the required -O3 optimization"

    if os.path.exists(LIB_PATH):
        os.remove(LIB_PATH)
    result = subprocess.run(
        ["make", "-B", "libsemver.so"],
        cwd=WORKSPACE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=20,
    )
    assert result.returncode == 0, f"Makefile build failed:\n{result.stdout}"
    assert os.path.isfile(LIB_PATH), f"Shared library missing after Makefile build: {LIB_PATH}"
    with open(LIB_PATH, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "libsemver.so is not an ELF shared library"

    start_server(clear_log=True)
    yield
    # The final integration test restarts the genuine submitted server and leaves it running.


def test_workspace_and_lib_exist():
    assert os.path.isdir(WORKSPACE_DIR), f"Workspace directory missing: {WORKSPACE_DIR}"
    assert os.path.isfile(LIB_PATH), f"Shared library missing: {LIB_PATH}"


def test_submitted_c_library_directly():
    lib = ctypes.CDLL(LIB_PATH)
    func = lib.get_latest_version
    func.argtypes = [ctypes.POINTER(ctypes.c_char_p), ctypes.c_int]
    func.restype = ctypes.c_char_p

    rng = random.SystemRandom()
    for _ in range(40):
        count = rng.randint(2, 25)
        versions = [
            f"{rng.randint(0, 100000)}.{rng.randint(0, 100000)}.{rng.randint(0, 100000)}"
            for _ in range(count)
        ]
        encoded = [value.encode("ascii") for value in versions]
        array = (ctypes.c_char_p * count)(*encoded)
        result = func(array, count)
        assert result is not None, "get_latest_version returned NULL"
        actual = result.decode("ascii")
        assert actual == expected_latest(versions), (
            f"C get_latest_version returned {actual!r} for {versions!r}"
        )


def test_resolver_source_uses_required_modules():
    with open(API_PATH, "r", encoding="utf-8") as handle:
        source = handle.read()
    tree = ast.parse(source, filename=API_PATH)
    imports_ctypes = any(
        (isinstance(node, ast.Import) and any(alias.name == "ctypes" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "ctypes")
        for node in ast.walk(tree)
    )
    imports_http_server = any(
        (isinstance(node, ast.Import) and any(alias.name == "http.server" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "http.server")
        for node in ast.walk(tree)
    )
    calls_cdll = any(
        isinstance(node, ast.Call)
        and (
            (isinstance(node.func, ast.Attribute) and node.func.attr == "CDLL")
            or (isinstance(node.func, ast.Name) and node.func.id == "CDLL")
        )
        for node in ast.walk(tree)
    )
    assert imports_ctypes and calls_cdll, "resolver_api.py must load the shared library using ctypes"
    assert imports_http_server, "resolver_api.py must use the standard-library http.server module"


def test_log_file_content():
    assert os.path.isfile(LOG_PATH), f"Log file missing: {LOG_PATH}"
    with open(LOG_PATH, "r", encoding="utf-8") as handle:
        content = handle.read()
    assert READY_MESSAGE in content, f"Log file does not contain the expected message: {READY_MESSAGE!r}"


def test_api_resolve_endpoint():
    payload = ["1.0.0", "1.0.1", "1.2.0", "2.2.9", "2.10.1", "2.3.0"]
    status, result = post_versions(payload)
    assert status == 200, f"Expected HTTP 200, got {status}"
    assert "latest" in result, "Response JSON is missing the 'latest' key"
    assert result["latest"] == "2.10.1", f"Expected latest version to be '2.10.1', got {result['latest']!r}"


def test_api_resolve_endpoint_edge_cases():
    status, result = post_versions(["0.9.9", "10.0.0", "9.99.99"])
    assert status == 200, f"Expected HTTP 200, got {status}"
    assert result.get("latest") == "10.0.0", f"Expected latest version to be '10.0.0', got {result.get('latest')!r}"


def test_api_with_unpredictable_inputs():
    rng = random.SystemRandom()
    for _ in range(15):
        versions = [
            f"{rng.randint(0, 50000)}.{rng.randint(0, 50000)}.{rng.randint(0, 50000)}"
            for _ in range(rng.randint(3, 18))
        ]
        status, result = post_versions(versions)
        assert status == 200, f"Expected HTTP 200, got {status}"
        assert result.get("latest") == expected_latest(versions), (
            f"API returned {result.get('latest')!r} for {versions!r}"
        )


def test_zz_api_result_is_supplied_by_ctypes_library():
    global SERVER
    stop_servers()
    backup = LIB_PATH + ".submission-backup"
    shutil.copy2(LIB_PATH, backup)
    token = f"ctypes_probe_{os.urandom(12).hex()}"
    probe_c = "/tmp/semver_ctypes_probe.c"
    with open(probe_c, "w", encoding="utf-8") as handle:
        handle.write(
            "const char* get_latest_version(const char** versions, int count) {\n"
            f"    return \"{token}\";\n"
            "}\n"
        )
    try:
        result = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-O3", probe_c, "-o", LIB_PATH],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=15,
        )
        assert result.returncode == 0, f"Failed to build verifier ctypes probe:\n{result.stdout}"
        start_server(clear_log=False)
        status, response = post_versions(["1.2.3", "99.0.0", "4.5.6"])
        assert status == 200, f"Expected HTTP 200, got {status}"
        assert response.get("latest") == token, (
            "API did not return the value supplied by get_latest_version in libsemver.so; "
            "it is not actually using the C function for resolution"
        )
    finally:
        stop_servers()
        if os.path.exists(backup):
            os.replace(backup, LIB_PATH)
        start_server(clear_log=False)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
