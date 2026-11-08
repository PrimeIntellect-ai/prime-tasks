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
import os
import pathlib
import random
import secrets
import signal
import socket
import subprocess
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
TOKEN = "Echo404"
ARCHIVE_PATH = "/home/user/archive.bin"


def source_candidates():
    candidates = []
    direct = [
        "/app/server.cpp",
        "/home/user/server.cpp",
        "/root/server.cpp",
        "/workspace/server.cpp",
        "/server.cpp",
    ]
    for path in direct:
        if os.path.isfile(path):
            candidates.append(path)

    for root in ("/app", "/home/user", "/root", "/workspace"):
        if not os.path.isdir(root):
            continue
        for directory, subdirs, files in os.walk(root):
            subdirs[:] = [d for d in subdirs if d not in {".git", "node_modules", "__pycache__"}]
            if "server.cpp" in files:
                candidates.append(os.path.join(directory, "server.cpp"))

    return sorted(set(candidates), key=lambda p: os.path.getmtime(p), reverse=True)


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10:
                        local_port = int(fields[1].split(":")[1], 16)
                        state = fields[3]
                        if local_port == port and state == "0A":
                            inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except OSError:
            continue
    return pids


def stop_existing_server():
    pids = listener_pids(8080)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids(8080):
        time.sleep(0.05)
    for pid in listener_pids(8080):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids(8080):
        time.sleep(0.05)


def wait_for_server(process):
    deadline = time.time() + 5
    while time.time() < deadline:
        if process.poll() is not None:
            pytest.fail(f"Compiled C++ server exited with status {process.returncode}")
        try:
            response = requests.get(BASE_URL, timeout=0.3)
            return
        except requests.exceptions.RequestException:
            time.sleep(0.1)
    pytest.fail("Compiled C++ server did not start listening on 127.0.0.1:8080")


@pytest.fixture(scope="session", autouse=True)
def setup_server():
    sources = source_candidates()
    assert sources, "No server.cpp was found"

    compile_errors = []
    source = None
    binary = "/tmp/submitted_cpp_server"
    for candidate in sources:
        result = subprocess.run(
            ["g++", "-std=c++17", "-O2", "-pthread", candidate, "-o", binary],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        if result.returncode == 0:
            source = candidate
            break
        compile_errors.append(f"{candidate}: {result.stderr[-1000:]}")

    assert source is not None, "No submitted server.cpp compiled successfully:\n" + "\n".join(compile_errors)
    assert pathlib.Path(binary).is_file(), "g++ did not produce a server executable"

    stop_existing_server()
    process = subprocess.Popen(
        [binary],
        cwd=os.path.dirname(source) or "/",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    wait_for_server(process)
    yield
    # Leave the submitted server running, as required by the task.


def encode_rle(data):
    output = bytearray()
    i = 0
    while i < len(data):
        value = data[i]
        count = 1
        while i + count < len(data) and data[i + count] == value and count < 255:
            count += 1
        output.extend((value, count))
        i += count
    return bytes(output)


def upload(payload, token=TOKEN):
    return requests.post(
        f"{BASE_URL}/upload",
        headers={"X-Backup-Token": token},
        data=payload,
        timeout=5,
    )


def download(token=TOKEN):
    return requests.get(
        f"{BASE_URL}/download",
        headers={"X-Backup-Token": token},
        timeout=5,
    )


def test_upload_success_and_archive_content():
    payload = b"ABBCCCDDDDEEEEE"
    try:
        response = upload(payload)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {BASE_URL}/upload: {e}")

    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    assert os.path.isfile(ARCHIVE_PATH), f"Archive file {ARCHIVE_PATH} was not created."

    with open(ARCHIVE_PATH, "rb") as f:
        content = f.read()

    expected_bytes = b'A\x01B\x02C\x03D\x04E\x05'
    assert content == expected_bytes, f"Archive content mismatch. Expected {expected_bytes}, got {content}"


def test_download_success():
    try:
        response = download()
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {BASE_URL}/download: {e}")

    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    assert response.text == "ABBCCCDDDDEEEEE", f"Expected response body 'ABBCCCDDDDEEEEE', got '{response.text}'"


def test_invalid_token():
    try:
        response = upload(b"TEST", token="Invalid")
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {BASE_URL}/upload: {e}")

    assert response.status_code != 200, f"Expected non-200 status for invalid token, got {response.status_code}"


def test_general_rle_and_runs_over_255():
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    alphabet = b"ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz0123456789"

    runs = [1, 2, 17, 254, 255, 256, 300, rng.randint(301, 700)]
    parts = []
    previous = None
    for length in runs:
        choices = [c for c in alphabet if c != previous]
        value = rng.choice(choices)
        parts.append(bytes([value]) * length)
        previous = value
    for _ in range(25):
        choices = [c for c in alphabet if c != previous]
        value = rng.choice(choices)
        parts.append(bytes([value]) * rng.randint(1, 280))
        previous = value

    payload = b"".join(parts)
    expected = encode_rle(payload)
    response = upload(payload)
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    assert os.path.isfile(ARCHIVE_PATH), f"Archive file {ARCHIVE_PATH} was not created."
    with open(ARCHIVE_PATH, "rb") as f:
        actual = f.read()
    assert actual == expected, "Archive does not contain the derived RLE encoding"

    response = download()
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    assert response.content == payload, "Downloaded body does not reproduce the uploaded payload"


def test_fresh_runtime_generated_payload():
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    payload = bytearray()
    previous = None
    for _ in range(80):
        value = rng.choice([c for c in range(33, 127) if c != previous])
        payload.extend(bytes([value]) * rng.randint(1, 40))
        previous = value
    payload = bytes(payload)

    response = upload(payload)
    assert response.status_code == 200
    with open(ARCHIVE_PATH, "rb") as f:
        assert f.read() == encode_rle(payload)
    response = download()
    assert response.status_code == 200
    assert response.content == payload
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
