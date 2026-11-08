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
import io
import json
import os
import secrets
import signal
import stat
import subprocess
import tarfile
import time

import requests

BASE_URL = "http://127.0.0.1:8080"
SOURCE = "/home/user/curator/main.go"
BINARY = "/tmp/curator-under-test"


def wait_for_server(timeout=5):
    """Wait for the server to respond on the required address."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            requests.get(f"{BASE_URL}/status", timeout=1)
            return True
        except requests.exceptions.RequestException:
            time.sleep(0.25)
    return False


def stop_port_8080():
    """Terminate processes listening on TCP port 8080 without external tools."""
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].endswith(":1F90") and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(pid))
                    break
        except (FileNotFoundError, PermissionError):
            pass

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.3)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def test_server_status():
    assert wait_for_server(), "Server is not listening on 127.0.0.1:8080 or did not respond in time"

    resp = requests.get(f"{BASE_URL}/status", timeout=2)
    assert resp.status_code == 200, f"Expected 200 OK for /status, got {resp.status_code}"

    data = resp.json()
    assert data.get("status") == "ready", f"Expected {{'status': 'ready'}}, got {data}"


def test_curate_unauthorized():
    assert wait_for_server(), "Server is not listening on 127.0.0.1:8080"

    resp = requests.post(f"{BASE_URL}/curate", timeout=2)
    assert resp.status_code == 401, f"Expected 401 Unauthorized for /curate without auth, got {resp.status_code}"


def test_curate_authorized():
    assert wait_for_server(), "Server is not listening on 127.0.0.1:8080"

    headers = {"Authorization": "Bearer delta charlie seven"}
    resp = requests.post(f"{BASE_URL}/curate", headers=headers, timeout=2)
    assert resp.status_code == 200, f"Expected 200 OK for /curate with valid auth, got {resp.status_code}"

    data = resp.json()
    assert "valid_files" in data, f"Response missing 'valid_files' key: {data}"

    valid_files = data["valid_files"]
    assert isinstance(valid_files, list), "'valid_files' should be a list"

    expected_files = {"/readme.txt", "/data/info.json"}
    actual_files = set(valid_files)

    assert actual_files == expected_files, f"Expected valid_files to be {expected_files}, but got {actual_files}"


def test_dynamic_audio_archive_and_cycles():
    assert os.path.exists(SOURCE), f"Missing required Go source file: {SOURCE}"
    assert stat.S_ISREG(os.lstat(SOURCE).st_mode), f"Required Go source is not a regular file: {SOURCE}"
    with open(SOURCE, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    assert "archive/tar" in source, "Go source must use the standard archive/tar parser"

    build = subprocess.run(
        ["go", "build", "-o", BINARY, SOURCE],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"Failed to build main.go:\n{build.stdout}"

    stop_port_8080()

    words = ["amber", "bravo", "cobalt", "falcon", "harbor", "lima", "maple", "november", "quartz", "river", "tango", "violet"]
    token = " ".join(secrets.choice(words) for _ in range(4))
    assert token != "delta charlie seven"
    subprocess.run(
        ["espeak", "-w", "/app/transmission.wav", token],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=15,
    )

    suffix = secrets.token_hex(6)
    top_file = f"manifest_{suffix}.txt"
    nested_dir = f"payload_{suffix}"
    deep_dir = f"{nested_dir}/records"
    nested_file = f"{deep_dir}/entry_{suffix}.json"
    loop_dir = f"cycle_{suffix}"

    with tarfile.open("/app/artifacts.tar", "w") as tf:
        for dirname in (nested_dir, deep_dir, loop_dir):
            info = tarfile.TarInfo(dirname)
            info.type = tarfile.DIRTYPE
            info.mode = 0o755
            tf.addfile(info)

        for name, content in (
            (top_file, secrets.token_bytes(19)),
            (nested_file, secrets.token_bytes(31)),
        ):
            info = tarfile.TarInfo(name)
            info.size = len(content)
            info.mode = 0o644
            tf.addfile(info, io.BytesIO(content))

        self_loop = tarfile.TarInfo(f"{loop_dir}/self")
        self_loop.type = tarfile.SYMTYPE
        self_loop.linkname = "."
        tf.addfile(self_loop)

        parent_loop = tarfile.TarInfo(f"{loop_dir}/parent")
        parent_loop.type = tarfile.SYMTYPE
        parent_loop.linkname = ".."
        tf.addfile(parent_loop)

        chained_loop = tarfile.TarInfo(f"{loop_dir}/chain")
        chained_loop.type = tarfile.SYMTYPE
        chained_loop.linkname = "self"
        tf.addfile(chained_loop)

    proc = subprocess.Popen(
        [BINARY],
        cwd="/home/user/curator",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        assert wait_for_server(timeout=8), "Rebuilt Go service did not start with randomized artifacts"

        resp = requests.get(f"{BASE_URL}/status", timeout=2)
        assert resp.status_code == 200
        assert resp.json().get("status") == "ready"

        resp = requests.post(f"{BASE_URL}/curate", timeout=2)
        assert resp.status_code == 401

        resp = requests.post(
            f"{BASE_URL}/curate",
            headers={"Authorization": "Bearer delta charlie seven"},
            timeout=2,
        )
        assert resp.status_code == 401, "The authorization token was hardcoded to the original transmission"

        resp = requests.post(
            f"{BASE_URL}/curate",
            headers={"Authorization": f"Bearer {token}"},
            timeout=3,
        )
        assert resp.status_code == 200, f"Expected 200 for randomized spoken token, got {resp.status_code}"
        data = resp.json()
        assert "valid_files" in data, f"Response missing 'valid_files': {data}"
        assert isinstance(data["valid_files"], list), "'valid_files' should be a list"

        expected = {f"/{top_file}", f"/{nested_file}"}
        actual = set(data["valid_files"])
        assert actual == expected, f"Expected randomized archive files {expected}, got {actual}"
        assert len(data["valid_files"]) == len(expected), "valid_files contains duplicate entries"
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
