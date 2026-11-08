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
import json
import os
import secrets
import socket
import subprocess
import tempfile
import time

import requests

REPO = "/home/user/cache-service"
MAIN_GO = os.path.join(REPO, "main.go")
SERVICE_BINARY = os.path.join(REPO, "cache-service")
RECOVERED_PORT = 9090
RECOVERED_TOKEN = "Z77-K9-BETA"


def test_service_health_endpoint_success():
    """Preserve the original check of the required running service."""
    url = f"http://127.0.0.1:{RECOVERED_PORT}/health"
    headers = {"Authorization": f"Bearer {RECOVERED_TOKEN}"}

    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        assert False, f"Failed to connect to the service at {url}. Is it running on port 9090? Error: {e}"

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
        assert data.get("status") == "ok", f"Expected response body to contain {{'status': 'ok'}}, got {data}"
    except ValueError:
        assert False, f"Expected JSON response, got: {response.text}"


def test_service_health_endpoint_unauthorized():
    """Preserve the original rejection check."""
    url = f"http://127.0.0.1:{RECOVERED_PORT}/health"
    headers = {"Authorization": "Bearer WRONG-TOKEN"}

    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        assert False, f"Failed to connect to the service at {url}. Error: {e}"

    assert response.status_code == 401, f"Expected HTTP 401 Unauthorized for bad token, got {response.status_code}."


def test_main_go_panic_removed():
    """Preserve the original source assertion."""
    assert os.path.isfile(MAIN_GO), f"The file {MAIN_GO} does not exist."
    with open(MAIN_GO, "r") as f:
        content = f.read()
    assert "panic(" not in content, f"The panic statement is still present in {MAIN_GO}."


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                        if local_port == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
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
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def test_required_go_binary_is_the_active_listener():
    """Ensure the demanded Go artifact, with recovered environment, is what is serving port 9090."""
    assert os.path.isfile(SERVICE_BINARY), f"Missing built service binary: {SERVICE_BINARY}"
    assert os.access(SERVICE_BINARY, os.X_OK), f"Service artifact is not executable: {SERVICE_BINARY}"

    with open(SERVICE_BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "cache-service is not an ELF executable"

    metadata = subprocess.run(
        ["go", "version", "-m", SERVICE_BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=10,
    )
    assert metadata.returncode == 0 and "go1." in metadata.stdout, \
        f"cache-service is not a Go-built executable: {metadata.stdout}"

    matching = []
    for pid in listener_pids(RECOVERED_PORT):
        try:
            if not os.path.samefile(f"/proc/{pid}/exe", SERVICE_BINARY):
                continue
            with open(f"/proc/{pid}/environ", "rb") as f:
                env_items = set(f.read().split(b"\0"))
            if (f"PORT={RECOVERED_PORT}".encode() in env_items and
                    f"AUTH_TOKEN={RECOVERED_TOKEN}".encode() in env_items):
                matching.append(pid)
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            continue

    assert matching, (
        "Port 9090 is not being served by the current ./cache-service binary "
        "started with the recovered PORT and AUTH_TOKEN environment values"
    )


def reserve_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def test_repaired_go_source_builds_and_handles_derived_configuration():
    """Build and execute main.go independently using verifier-derived values."""
    assert os.path.isdir(os.path.join(REPO, ".git")), f"{REPO} is not a Git repository"

    with tempfile.TemporaryDirectory(prefix="cache-verifier-") as tmp:
        candidate = os.path.join(tmp, "cache-service-test")
        build = subprocess.run(
            ["go", "build", "-o", candidate, "main.go"],
            cwd=REPO,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=45,
        )
        assert build.returncode == 0, f"main.go does not build successfully:\n{build.stdout}"

        port = reserve_port()
        token = "verify-" + secrets.token_urlsafe(24)
        bad_tokens = [
            "wrong-" + secrets.token_urlsafe(18),
            token + "-incorrect",
            secrets.token_hex(20),
        ]
        env = os.environ.copy()
        env["PORT"] = str(port)
        env["AUTH_TOKEN"] = token
        proc = subprocess.Popen(
            [candidate],
            cwd=REPO,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        try:
            url = f"http://127.0.0.1:{port}/health"
            deadline = time.time() + 8
            response = None
            last_error = None
            while time.time() < deadline:
                if proc.poll() is not None:
                    out, err = proc.communicate()
                    assert False, f"Built Go service exited early. stdout={out!r}, stderr={err!r}"
                try:
                    response = requests.get(
                        url,
                        headers={"Authorization": f"Bearer {token}"},
                        timeout=1,
                    )
                    break
                except requests.exceptions.RequestException as exc:
                    last_error = exc
                    time.sleep(0.1)

            assert response is not None, f"Built Go service did not start on derived port {port}: {last_error}"
            assert response.status_code == 200, f"Derived valid token received HTTP {response.status_code}: {response.text}"
            assert response.json().get("status") == "ok", f"Unexpected health JSON: {response.text}"

            for bad in bad_tokens:
                rejected = requests.get(
                    url,
                    headers={"Authorization": f"Bearer {bad}"},
                    timeout=2,
                )
                assert rejected.status_code == 401, \
                    f"Verifier-derived bad token was not rejected: HTTP {rejected.status_code}"

            missing = requests.get(url, timeout=2)
            assert missing.status_code == 401, \
                f"Missing authorization was not rejected: HTTP {missing.status_code}"
            assert proc.poll() is None, "Built Go service stopped while handling /health requests"
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=3)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
