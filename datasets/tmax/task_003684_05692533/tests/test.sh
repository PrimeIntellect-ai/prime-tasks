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
import ast
import hashlib
import os
import re
import signal
import subprocess
import time

import pytest
import requests

APP_DIR = "/app/test-util"
SETUP_PATH = os.path.join(APP_DIR, "setup.py")
SERVER_PATH = os.path.join(APP_DIR, "server.sh")
IMAGE_PATH = "/app/server_config.png"
EXPECTED_PORT = 9055
EXPECTED_TOKEN = "GO_MOCK_XYZ123"


def read_config():
    result = subprocess.run(
        ["tesseract", IMAGE_PATH, "stdout"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"OCR failed: {result.stderr}"
    port_match = re.search(r"PORT\s*:\s*(\d+)", result.stdout, re.IGNORECASE)
    token_match = re.search(r"TOKEN\s*:\s*([A-Za-z0-9_]+)", result.stdout, re.IGNORECASE)
    assert port_match, f"Could not extract port from image OCR: {result.stdout!r}"
    assert token_match, f"Could not extract token from image OCR: {result.stdout!r}"
    return int(port_match.group(1)), token_match.group(1)


def listening_inodes(port):
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                        if local_port == port:
                            found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def pids_for_inodes(inodes):
    pids = set()
    if not inodes:
        return pids
    targets = {f"socket:[{inode}]" for inode in inodes}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) in targets:
                        pids.add(int(entry))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return pids


def stop_old_server(port):
    # Stop prior invocations of the required artifact, then remove any remaining
    # listener so the tested listener can only have appeared by executing server.sh.
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="ignore")
            cwd = os.path.realpath(f"/proc/{entry}/cwd")
            if "server.sh" in cmdline and cwd == APP_DIR:
                os.kill(int(entry), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError, OSError):
            pass

    time.sleep(0.3)
    for _ in range(20):
        inodes = listening_inodes(port)
        if not inodes:
            return
        for pid in pids_for_inodes(inodes):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        time.sleep(0.1)
    assert not listening_inodes(port), f"Could not clear the old listener on port {port}"


def wait_for_listener(port, process):
    deadline = time.time() + 8
    while time.time() < deadline:
        if listening_inodes(port):
            return
        if process.poll() is not None:
            pytest.fail(f"server.sh exited before opening port {port} (exit {process.returncode})")
        time.sleep(0.1)
    pytest.fail(f"server.sh did not open port {port}")


def test_setup_py_syntax():
    """Verify that setup.py has valid Python syntax."""
    assert os.path.isfile(SETUP_PATH), f"File {SETUP_PATH} does not exist."
    with open(SETUP_PATH, "r") as f:
        content = f.read()
    try:
        ast.parse(content)
    except SyntaxError as e:
        pytest.fail(f"setup.py still contains syntax errors: {e}")


def test_pip_install_succeeds():
    """Verify the package requirement by actually installing the local project."""
    result = subprocess.run(
        ["python3", "-m", "pip", "install", "."],
        cwd=APP_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert result.returncode == 0, f"pip install . failed:\n{result.stdout}"


@pytest.fixture(scope="module")
def running_server():
    assert os.path.isfile(SERVER_PATH), f"File {SERVER_PATH} does not exist."
    assert os.access(SERVER_PATH, os.X_OK), f"File {SERVER_PATH} is not executable."

    syntax = subprocess.run(
        ["bash", "-n", SERVER_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert syntax.returncode == 0, f"server.sh has invalid Bash syntax: {syntax.stderr}"

    port, token = read_config()
    assert port == EXPECTED_PORT, f"Image port changed: expected {EXPECTED_PORT}, got {port}"
    assert token == EXPECTED_TOKEN, f"Image token changed: expected {EXPECTED_TOKEN}, got {token}"

    stop_old_server(port)
    process = subprocess.Popen(
        ["/bin/bash", SERVER_PATH],
        cwd=APP_DIR,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    wait_for_listener(port, process)
    # Intentionally do not stop it: the instruction requires leaving it running.
    return port, token


def test_server_valid_request(running_server):
    """Verify that server.sh responds correctly to a valid request."""
    port, token = running_server
    url = f"http://127.0.0.1:{port}/verify"
    headers = {"Authorization": f"Bearer {token}"}
    expected_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()

    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server on port {port}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    assert response.text.strip() == expected_hash, f"Expected body to be {expected_hash}, got {response.text}"
    assert response.content == expected_hash.encode("ascii"), (
        f"Response body must be exactly the hex hash with no extra whitespace; got {response.content!r}"
    )


def test_server_invalid_request(running_server):
    """Verify that the server responds with 401 Unauthorized for missing/incorrect auth."""
    port, _ = running_server
    url = f"http://127.0.0.1:{port}/verify"

    try:
        response_missing = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server on port {port}: {e}")
    assert response_missing.status_code == 401, (
        f"Expected status code 401 for missing auth, got {response_missing.status_code}"
    )

    headers = {"Authorization": "Bearer WRONG_TOKEN"}
    try:
        response_wrong = requests.get(url, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server on port {port}: {e}")
    assert response_wrong.status_code == 401, (
        f"Expected status code 401 for incorrect auth, got {response_wrong.status_code}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
