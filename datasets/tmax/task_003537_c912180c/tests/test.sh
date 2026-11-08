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

cat << 'PY_EOF' > /tmp/verify_diagnostic_server.py
import os
import secrets
import signal
import socket
import subprocess
import tempfile
import time

import requests

SERVER = "/home/user/diag_server"
SOURCE = "/home/user/diagnostic_server.cpp"
BASE_URL = "http://127.0.0.1:9090"
PIN = "8294"


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10 or fields[3] != "0A":
                        continue
                    if int(fields[1].split(":")[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def clear_port():
    for pid in listener_pids(9090):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline:
        if not listener_pids(9090):
            return
        time.sleep(0.05)
    raise AssertionError("Could not clear port 9090 before testing the submitted server")


def wait_for_port(proc):
    deadline = time.time() + 5
    while time.time() < deadline:
        if proc.poll() is not None:
            raise AssertionError(f"Server exited during startup with status {proc.returncode}")
        try:
            with socket.create_connection(("127.0.0.1", 9090), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise AssertionError("Server did not listen on port 9090")


def start_server(path):
    clear_port()
    proc = subprocess.Popen(
        [path],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    wait_for_port(proc)

    # Ensure the process launched for the test is the requested native artifact.
    assert os.stat(f"/proc/{proc.pid}/exe").st_ino == os.stat(path).st_ino, \
        f"The process under test is not executing {path}"
    return proc


def stop_server(proc):
    if proc is not None and proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)
    clear_port()


def exercise_server(proc):
    # Authentication must gate diagnostics on a fresh process.
    r_unauth = requests.get(f"{BASE_URL}/diagnostics", timeout=3)
    assert r_unauth.status_code == 401, \
        f"Expected HTTP 401 for diagnostics before authentication, got {r_unauth.status_code}"

    bad_pin = secrets.token_hex(8)
    assert PIN not in bad_pin
    r_bad = requests.post(f"{BASE_URL}/auth", data=bad_pin, timeout=3)
    assert r_bad.status_code == 403, \
        f"Expected HTTP 403 for an incorrect PIN, got {r_bad.status_code}"

    r_still_unauth = requests.get(f"{BASE_URL}/diagnostics", timeout=3)
    assert r_still_unauth.status_code == 401, \
        "An incorrect PIN unexpectedly enabled diagnostics"

    # Preserve the original verifier's correct-PIN assertion.
    r_auth = requests.post(f"{BASE_URL}/auth", data=PIN, timeout=3)
    assert r_auth.status_code == 200, \
        f"Expected HTTP 200 for correct PIN, got {r_auth.status_code}"

    # Repeat the crashing operation to ensure the process survives the corrupting path.
    for _ in range(8):
        r_diag = requests.get(f"{BASE_URL}/diagnostics", timeout=3)
        assert r_diag.status_code == 200, \
            f"Expected HTTP 200 for diagnostics after auth, got {r_diag.status_code}"
        assert "Diagnostic" in r_diag.text or "CPU" in r_diag.text, \
            "Response did not contain expected diagnostic data"
        assert proc.poll() is None, "Server crashed while serving /diagnostics"

    r_missing = requests.get(f"{BASE_URL}/not-an-endpoint-{secrets.token_hex(6)}", timeout=3)
    assert r_missing.status_code == 404, \
        f"Expected HTTP 404 for an unknown endpoint, got {r_missing.status_code}"
    assert proc.poll() is None, "Server exited after handling requests"


def main():
    # Preserve the original existence assertion and require a runnable native binary.
    assert os.path.isfile(SERVER), \
        "The compiled executable /home/user/diag_server is missing."
    assert os.access(SERVER, os.X_OK), \
        "/home/user/diag_server is not executable"
    with open(SERVER, "rb") as f:
        assert f.read(4) == b"\x7fELF", \
            "/home/user/diag_server is not a native ELF executable"
    assert os.path.isfile(SOURCE), "The required C++ source file is missing"

    submitted = None
    rebuilt = None
    submitted_ok = False
    rebuilt_path = tempfile.mktemp(prefix="diag_server_from_source_", dir="/tmp")

    try:
        # Execute and test the exact artifact the instruction required.
        submitted = start_server(SERVER)
        exercise_server(submitted)
        submitted_ok = True
        stop_server(submitted)
        submitted = None

        # Independently compile and exercise the submitted source. Fortification makes
        # the original overflowing strcpy fail reliably instead of trusting a fake server.
        result = subprocess.run(
            ["g++", "-std=c++17", "-O2", "-D_FORTIFY_SOURCE=2",
             "-fstack-protector-all", SOURCE, "-o", rebuilt_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, \
            f"The submitted C++ source does not compile:\n{result.stderr}"
        rebuilt = start_server(rebuilt_path)
        exercise_server(rebuilt)
        stop_server(rebuilt)
        rebuilt = None
    finally:
        if submitted is not None:
            stop_server(submitted)
        if rebuilt is not None:
            stop_server(rebuilt)
        try:
            os.unlink(rebuilt_path)
        except FileNotFoundError:
            pass

        # Restore the required final state after destructive verification.
        if submitted_ok:
            final_proc = start_server(SERVER)
            assert final_proc.poll() is None


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_diagnostic_server.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
