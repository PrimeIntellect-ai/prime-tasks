#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import shutil
import signal
import stat
import string
import subprocess
import time

import pytest
import requests

EXPECTED_ORDER = [
    "base_init.patch",
    "core_utils.patch",
    "math_routines.patch",
    "analytics_engine.patch",
]
PROJECT = "/home/user/build_service"
BINARY = "/home/user/legacy_lib/analytics_engine"
SERVER_PROCESS = None


def test_patch_order_file():
    patch_order_path = "/home/user/patch_order.txt"
    assert os.path.isfile(patch_order_path), f"Patch order log is missing: {patch_order_path}"

    with open(patch_order_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == EXPECTED_ORDER, f"Patch order is incorrect. Expected {EXPECTED_ORDER}, got {lines}"


def test_patches_are_present_in_legacy_source_and_project_builds():
    source_path = "/home/user/legacy_lib/main.cpp"
    assert os.path.isfile(source_path), f"Legacy source is missing: {source_path}"

    with open(source_path, "r", encoding="utf-8") as f:
        source = f.read()

    markers = ["base_init", "core_utils", "math_routines"]
    positions = [source.find(marker) for marker in markers]
    assert all(pos >= 0 for pos in positions), "Legacy source does not contain the changes from all prerequisite patches"
    assert positions == sorted(positions), "Patch changes are not present in dependency order in main.cpp"
    assert "Analytics Engine V2: 0 memory leaks. Execution successful." in source, "analytics_engine patch output is absent from main.cpp"
    assert "i<=10" not in source.replace(" ", ""), "The patched off-by-one loop was not repaired"
    if "new int[10]" in source:
        assert "delete[]" in source, "The allocation introduced by the patch is still leaked"

    build = subprocess.run(["make", "-B", "all"], cwd="/home/user/legacy_lib", capture_output=True, text=True, timeout=60)
    assert build.returncode == 0, f"Legacy C++ source does not build with its Makefile.\nStdout: {build.stdout}\nStderr: {build.stderr}"

    tests = subprocess.run(["make", "test"], cwd="/home/user/legacy_lib", capture_output=True, text=True, timeout=30)
    assert tests.returncode == 0, f"make test failed.\nStdout: {tests.stdout}\nStderr: {tests.stderr}"
    assert "Analytics Engine V2: 0 memory leaks. Execution successful." in tests.stdout

    assert os.path.isfile(BINARY), f"Compiled binary missing: {BINARY}"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "analytics_engine is not a compiled ELF executable"


def test_cpp_binary_valgrind():
    assert os.path.isfile(BINARY), f"Compiled binary missing: {BINARY}"

    result = subprocess.run(
        ["valgrind", "--error-exitcode=1", "--leak-check=full", BINARY],
        capture_output=True,
        text=True,
        timeout=30,
    )

    assert result.returncode == 0, f"Valgrind failed. The C++ binary has memory issues or crashed.\nStdout: {result.stdout}\nStderr: {result.stderr}"


def test_rust_service_graph():
    url = "http://127.0.0.1:8080/graph"
    try:
        response = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Rust service at {url}: {e}")

    assert response.status_code == 200, f"Expected 200 OK for GET /graph, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from /graph is not valid JSON: {response.text}")

    assert data == EXPECTED_ORDER, f"Expected /graph to return {EXPECTED_ORDER}, got {data}"


def test_rust_service_verify_unauthorized():
    url = "http://127.0.0.1:8080/verify"
    try:
        response = requests.post(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Rust service at {url}: {e}")

    assert response.status_code in [401, 403], f"Expected 401 or 403 for POST /verify without auth, got {response.status_code}"


def test_rust_service_verify_authorized():
    url = "http://127.0.0.1:8080/verify"
    headers = {"Authorization": "Bearer artifact-token-992"}
    try:
        response = requests.post(url, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Rust service at {url}: {e}")

    assert response.status_code == 200, f"Expected 200 OK for POST /verify with auth, got {response.status_code}. Response: {response.text}"

    expected_text = "Analytics Engine V2: 0 memory leaks. Execution successful."
    assert expected_text in response.text, f"Expected '{expected_text}' in response body, got '{response.text}'"


def listening_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        if not os.path.exists(table):
            continue
        with open(table, "r") as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) >= 10 and fields[3] == "0A":
                    _, port_hex = fields[1].rsplit(":", 1)
                    if int(port_hex, 16) == port:
                        result.add(fields[9])
    return result


def kill_port_processes(port):
    inodes = listening_inodes(port)
    pids = set()
    for proc in glob.glob("/proc/[0-9]*"):
        try:
            for fd in os.listdir(os.path.join(proc, "fd")):
                try:
                    target = os.readlink(os.path.join(proc, "fd", fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(os.path.basename(proc)))
        except (FileNotFoundError, PermissionError):
            pass
    for pid in pids:
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    deadline = time.time() + 3
    while listening_inodes(port) and time.time() < deadline:
        time.sleep(0.05)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def build_rust_binary():
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "build_service is missing Cargo.toml"
    rust_sources = glob.glob(os.path.join(PROJECT, "**", "*.rs"), recursive=True)
    assert rust_sources, "build_service contains no Rust source files"

    result = subprocess.run(
        ["cargo", "build", "--message-format=json"],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, f"Rust project failed to compile.\nStdout: {result.stdout}\nStderr: {result.stderr}"

    executables = []
    for line in result.stdout.splitlines():
        try:
            message = json.loads(line)
        except ValueError:
            continue
        if message.get("reason") == "compiler-artifact" and "bin" in message.get("target", {}).get("kind", []):
            executable = message.get("executable")
            if executable:
                executables.append(executable)
    assert executables, "Cargo did not produce a Rust binary target"
    executable = executables[-1]
    assert os.path.isfile(executable) and os.access(executable, os.X_OK), "Cargo binary is missing or not executable"
    return executable


def wait_for_service(process):
    deadline = time.time() + 8
    last_error = None
    while time.time() < deadline:
        assert process.poll() is None, "The Cargo-built Rust server exited before serving requests"
        try:
            response = requests.get("http://127.0.0.1:8080/graph", timeout=0.3)
            if response.status_code == 200:
                return response
        except requests.RequestException as error:
            last_error = error
        time.sleep(0.1)
    pytest.fail(f"Cargo-built Rust server did not start on 127.0.0.1:8080: {last_error}")


def test_zz_cargo_built_service_is_real_and_executes_cpp_binary():
    global SERVER_PROCESS
    executable = build_rust_binary()
    kill_port_processes(8080)

    SERVER_PROCESS = subprocess.Popen(
        [executable],
        cwd=PROJECT,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    response = wait_for_service(SERVER_PROCESS)
    assert response.json() == EXPECTED_ORDER

    listeners = []
    with open("/proc/net/tcp", "r") as f:
        next(f, None)
        for line in f:
            fields = line.split()
            if len(fields) >= 4 and fields[3] == "0A":
                address, port_hex = fields[1].split(":")
                if int(port_hex, 16) == 8080:
                    listeners.append(address)
    assert listeners, "No IPv4 listener was found on port 8080"
    assert all(address == "0100007F" for address in listeners), f"Service is not bound strictly to 127.0.0.1:8080: {listeners}"

    wrong = requests.post(
        "http://127.0.0.1:8080/verify",
        headers={"Authorization": "Bearer wrong-token"},
        timeout=3,
    )
    assert wrong.status_code in [401, 403], "The exact authorization token is not enforced"

    normal = requests.post(
        "http://127.0.0.1:8080/verify",
        headers={"Authorization": "Bearer artifact-token-992"},
        timeout=5,
    )
    assert normal.status_code == 200
    assert "Analytics Engine V2: 0 memory leaks. Execution successful." in normal.text

    with open(BINARY, "rb") as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(BINARY).st_mode)
    nonce = "dynamic-exec-" + "".join(random.choice(string.ascii_letters) for _ in range(20))
    try:
        with open(BINARY, "wb") as f:
            f.write(("#!/bin/sh\nprintf '%s\\n' '" + nonce + "'\n").encode())
        os.chmod(BINARY, 0o755)
        dynamic = requests.post(
            "http://127.0.0.1:8080/verify",
            headers={"Authorization": "Bearer artifact-token-992"},
            timeout=5,
        )
        assert dynamic.status_code == 200
        assert nonce in dynamic.text, "POST /verify did not execute /home/user/legacy_lib/analytics_engine"
    finally:
        with open(BINARY, "wb") as f:
            f.write(original)
        os.chmod(BINARY, original_mode)

    assert SERVER_PROCESS.poll() is None, "The Cargo-built Rust server did not stay running"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
