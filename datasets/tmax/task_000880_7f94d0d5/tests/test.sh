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
import gzip
import os
import signal
import subprocess
import time

import pytest
import requests

APP_DIR = "/app/wal-serve-v1.0"
BINARY = os.path.join(APP_DIR, "wal_server")
DATASET = "/home/user/dataset/001.wal.gz"
URL = "http://127.0.0.1:9090/records"


def request_with_retry(url=URL, retries=20):
    last_error = None
    for _ in range(retries):
        try:
            return requests.get(url, timeout=2)
        except requests.exceptions.RequestException as exc:
            last_error = exc
            time.sleep(0.2)
    pytest.fail(f"Failed to connect to {url}: {last_error}")


def listening_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            pass
    return result


def stop_listeners(port):
    pids = listening_pids(port)
    for pid in pids:
        os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 3
    while time.time() < deadline and listening_pids(port):
        time.sleep(0.1)
    for pid in listening_pids(port):
        os.kill(pid, signal.SIGKILL)
    deadline = time.time() + 2
    while time.time() < deadline and listening_pids(port):
        time.sleep(0.1)
    assert not listening_pids(port), f"Could not stop the existing listener on port {port}"


def test_makefile_fixed():
    makefile_path = os.path.join(APP_DIR, "Makefile")
    assert os.path.isfile(makefile_path), f"Makefile is missing at {makefile_path}."

    with open(makefile_path, "r") as f:
        content = f.read()

    assert "-lz" in content, "Makefile was not updated to include the '-lz' linker flag."


def test_server_cpp_fixed():
    server_cpp_path = os.path.join(APP_DIR, "server.cpp")
    assert os.path.isfile(server_cpp_path), f"server.cpp is missing at {server_cpp_path}."

    with open(server_cpp_path, "r") as f:
        content = f.read()

    assert "/var/old_data" not in content, "server.cpp still contains the buggy hardcoded path '/var/old_data'."
    assert "/home/user/dataset" in content, "server.cpp does not contain the correct dataset path '/home/user/dataset'."


def test_server_running_and_serving_data():
    response = request_with_retry(retries=3)
    assert response.status_code == 200, f"Expected HTTP 200 OK, but got {response.status_code}. Response body: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, but failed to parse. Response body: {response.text}")

    assert data.get("status") == "success", f"Expected status 'success' in JSON, got: {data.get('status')}"
    assert "records" in data, "Expected 'records' key in JSON response."
    assert data["records"] == 1, f"Expected exactly one parsed record, got: {data['records']}"

    pids = listening_pids(9090)
    assert pids, "No process is listening on port 9090."
    assert os.path.isfile(BINARY), f"Compiled server binary is missing at {BINARY}."
    assert any(os.path.samefile(f"/proc/{pid}/exe", BINARY) for pid in pids), \
        "The listener on port 9090 is not the compiled wal_server binary."


def test_clean_rebuild_and_dataset_read():
    stop_listeners(9090)

    for artifact in (BINARY, os.path.join(APP_DIR, "server.o")):
        try:
            os.remove(artifact)
        except FileNotFoundError:
            pass

    build = subprocess.run(
        ["make", "-B", "wal_server"],
        cwd=APP_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert build.returncode == 0, f"A clean rebuild failed:\n{build.stdout}"
    assert os.path.isfile(BINARY), "make succeeded without producing wal_server."
    assert os.access(BINARY, os.X_OK), "wal_server is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "wal_server is not a compiled ELF executable."

    log = open("/tmp/wal_server_verifier.log", "wb")
    process = subprocess.Popen(
        [BINARY, "9090"],
        cwd=APP_DIR,
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )

    original_dataset = open(DATASET, "rb").read()
    try:
        response = request_with_retry()
        assert response.status_code == 200, response.text
        data = response.json()
        assert data.get("status") == "success"
        assert data.get("records") == 1, f"Expected one record, got {data.get('records')}"

        # An empty, valid gzip stream must produce the application's read-failure response.
        with open(DATASET, "wb") as f:
            f.write(gzip.compress(b""))
        response = request_with_retry()
        assert response.status_code == 500, \
            f"Server did not react to an empty gzip dataset; got {response.status_code}: {response.text}"
        assert "read failed" in response.text

        # Restoring nonempty gzip data must make the same running binary succeed again.
        with open(DATASET, "wb") as f:
            f.write(gzip.compress(b"verifier record\n"))
        response = request_with_retry()
        assert response.status_code == 200, response.text
        data = response.json()
        assert data.get("status") == "success"
        assert data.get("records") == 1
        assert process.poll() is None, "The rebuilt wal_server exited unexpectedly."
    finally:
        with open(DATASET, "wb") as f:
            f.write(original_dataset)

    # Verify that the restored real dataset is still served, and leave this server running.
    response = request_with_retry()
    assert response.status_code == 200, response.text
    assert response.json().get("records") == 1
    assert process.poll() is None
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
