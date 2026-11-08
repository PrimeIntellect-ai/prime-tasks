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
import ctypes
import os
import random
import signal
import subprocess
import time
from pathlib import Path

import pytest
import requests

PORT = 8282
TOKEN = "TRITON-77X-912"
URL = f"http://127.0.0.1:{PORT}/api/v1/process"
LIB = Path("/home/user/clib/libsorter.so")
CLIB = Path("/home/user/clib")
SERVER = Path("/home/user/server.py")


def post(payload, token=TOKEN, timeout=5):
    headers = {"Authorization": f"Bearer {token}"} if token is not None else {}
    return requests.post(URL, headers=headers, json=payload, timeout=timeout)


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                inodes.add(fields[9])

    owners = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        fd_dir = proc / "fd"
        try:
            fds = list(fd_dir.iterdir())
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                owners.add(int(proc.name))
    return owners


def stop_listener(port):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids(port):
        time.sleep(0.1)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids(port):
        time.sleep(0.1)
    assert not listener_pids(port), f"Could not stop the existing listener on port {port}"


def wait_for_server(proc, timeout=20):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        if proc.poll() is not None:
            output = Path("/tmp/audited_server.log").read_text(errors="replace")
            pytest.fail(f"server.py exited with status {proc.returncode}:\n{output}")
        try:
            response = requests.post(URL, json={"arrays": [[1]]}, timeout=0.5)
            if response.status_code == 401:
                return
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.2)
    pytest.fail(f"Restarted server did not become ready: {last_error}")


def test_libsorter_built():
    assert os.path.isfile(LIB), "libsorter.so was not built in /home/user/clib/"


def test_makefile_builds_real_shared_library_and_export_works():
    makefile = (CLIB / "Makefile").read_text()
    assert "-shared" in makefile, "Makefile does not use the -shared linker flag"
    assert "-fPIC" in makefile, "Makefile does not compile position-independent code with -fPIC"

    LIB.unlink()
    result = subprocess.run(
        ["make", "-B"], cwd=CLIB, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=20
    )
    assert result.returncode == 0, f"The corrected Makefile failed:\n{result.stdout}"
    assert LIB.is_file(), "Running make did not create libsorter.so"
    assert LIB.read_bytes()[:4] == b"\x7fELF", "libsorter.so is not an ELF binary"

    header = subprocess.run(
        ["readelf", "-h", str(LIB)], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=10
    )
    assert header.returncode == 0 and "DYN (Shared object file)" in header.stdout, \
        f"libsorter.so is not a shared object:\n{header.stdout}"

    library = ctypes.CDLL(str(LIB))
    sorter = library.sort_array
    sorter.argtypes = [ctypes.POINTER(ctypes.c_int), ctypes.c_int]
    sorter.restype = None
    rng = random.SystemRandom()
    for _ in range(6):
        values = [rng.randint(-5000, 5000) for _ in range(rng.randint(3, 30))]
        array = (ctypes.c_int * len(values))(*values)
        sorter(array, len(values))
        assert list(array) == sorted(values), "sort_array did not correctly sort a generated input"


def test_server_source_uses_ctypes():
    source = SERVER.read_text()
    assert "ctypes" in source and "CDLL" in source, "server.py does not load the C library through ctypes"


def test_server_unauthorized():
    try:
        response = post({"arrays": [[1, 2], [3, 4]]}, token=None)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")
    assert response.status_code == 401, f"Expected 401 Unauthorized for missing auth, got {response.status_code}"


def test_server_rejects_incorrect_token():
    response = post({"arrays": [[4, 1], [3, 2]]}, token="incorrect-token")
    assert response.status_code == 401, f"Expected 401 for an incorrect token, got {response.status_code}"


def test_server_authorized_process():
    payload = {"arrays": [[10, 2, 8], [1, 9]]}
    try:
        response = post(payload)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")
    assert "result" in data, f"Response JSON missing 'result' key. Got: {data}"
    assert data["result"] == [1, 2, 8, 9, 10], f"Expected result [1, 2, 8, 9, 10], got {data['result']}"


def test_server_handles_generated_inputs():
    rng = random.SystemRandom()
    for _ in range(7):
        arrays = []
        for _ in range(rng.randint(2, 6)):
            arrays.append([rng.randint(-10000, 10000) for _ in range(rng.randint(1, 9))])
        expected = sorted(value for array in arrays for value in array)
        response = post({"arrays": arrays})
        assert response.status_code == 200, f"Generated request failed: {response.status_code} {response.text}"
        assert response.json() == {"result": expected}, \
            f"Incorrect merge/sort for generated arrays {arrays}: {response.text}"


def test_z_server_actually_uses_loaded_sort_array():
    # Replace the already-validated library with an ABI-compatible audit library,
    # restart server.py, and verify that the endpoint returns its distinctive mutation.
    # A Python-only sorter or hardcoded response cannot pass this check.
    audit_source = Path("/tmp/audit_sorter.c")
    audit_source.write_text(r'''
#include <stdio.h>
void sort_array(int *arr, int len) {
    for (int i = 0; i < len - 1; i++) {
        for (int j = 0; j < len - i - 1; j++) {
            if (arr[j] > arr[j + 1]) {
                int tmp = arr[j]; arr[j] = arr[j + 1]; arr[j + 1] = tmp;
            }
        }
    }
    for (int i = 0; i < len; i++) arr[i] += 1000003;
    FILE *f = fopen("/tmp/sort_array_called", "w");
    if (f) { fputs("called", f); fclose(f); }
}
''')
    subprocess.run(
        ["gcc", "-shared", "-fPIC", "-o", str(LIB), str(audit_source)],
        check=True, timeout=20
    )
    marker = Path("/tmp/sort_array_called")
    marker.unlink(missing_ok=True)

    stop_listener(PORT)
    log = open("/tmp/audited_server.log", "w")
    proc = subprocess.Popen(
        ["python3", str(SERVER)], cwd="/home/user", stdout=log,
        stderr=subprocess.STDOUT, start_new_session=True
    )
    try:
        wait_for_server(proc)
        marker.unlink(missing_ok=True)
        rng = random.SystemRandom()
        arrays = [
            [rng.randint(-200, 200) for _ in range(5)],
            [rng.randint(-200, 200) for _ in range(4)],
        ]
        merged = [value for array in arrays for value in array]
        expected = [value + 1000003 for value in sorted(merged)]
        response = post({"arrays": arrays})
        assert response.status_code == 200, response.text
        assert response.json() == {"result": expected}, \
            "The endpoint did not return the array mutated by the loaded sort_array function"
        assert marker.is_file(), "The server did not invoke sort_array from libsorter.so"
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        log.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
