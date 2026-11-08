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
import stat
import subprocess
import time

import pytest
import requests

SOURCE = "/home/user/diag_daemon.cpp"
BINARY = "/home/user/diag_daemon"


def test_required_cpp_daemon_artifacts_and_listener():
    """Verify the required build artifacts exist and the compiled daemon owns port 8080."""
    assert os.path.isfile(SOURCE), f"Missing required C++ source file: {SOURCE}"
    assert os.path.isfile(BINARY), f"Missing required compiled daemon: {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Compiled daemon is not executable: {BINARY}"

    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not an ELF compiled executable"

    with open(SOURCE, "r", errors="replace") as f:
        source_text = f.read()

    assert "sys/socket.h" in source_text, "C++ daemon does not include the required POSIX socket header"
    for api in ("socket", "bind", "listen", "accept"):
        assert api + "(" in source_text or api + " (" in source_text, \
            f"C++ daemon source does not use the POSIX {api} API"
    assert "boost/" not in source_text.lower(), "Third-party Boost networking code is not allowed"
    assert "crow.h" not in source_text.lower(), "Third-party Crow networking code is not allowed"

    build_check = "/tmp/diag_daemon_build_check"
    result = subprocess.run(
        ["g++", "-pthread", SOURCE, "-o", build_check],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Required C++ source does not compile:\n{result.stderr}"

    listener_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10:
                        local_address = fields[1]
                        state = fields[3]
                        inode = fields[9]
                        if state == "0A" and int(local_address.rsplit(":", 1)[1], 16) == 8080:
                            listener_inodes.add(inode)
        except FileNotFoundError:
            pass

    assert listener_inodes, "No process is listening on port 8080"

    owners = []
    for proc_dir in glob.glob("/proc/[0-9]*"):
        pid = os.path.basename(proc_dir)
        for fd in glob.glob(os.path.join(proc_dir, "fd", "*")):
            try:
                target = os.readlink(fd)
            except (FileNotFoundError, PermissionError, OSError):
                continue
            if target.startswith("socket:[") and target[8:-1] in listener_inodes:
                try:
                    exe = os.readlink(os.path.join(proc_dir, "exe"))
                except (FileNotFoundError, PermissionError, OSError):
                    continue
                owners.append((pid, exe))
                break

    assert owners, "Could not identify the process owning the port 8080 listener"
    for pid, exe in owners:
        assert not exe.endswith(" (deleted)"), f"Listener process {pid} is running a deleted executable"
        try:
            is_required_binary = os.path.samefile(exe, BINARY)
        except (FileNotFoundError, OSError):
            is_required_binary = False
        assert is_required_binary, \
            f"Port 8080 is owned by {exe}, not the required compiled daemon {BINARY}"


def test_telemetry_server():
    """Verify that the daemon responds to GET /api/v1/fault with the expected JSON payload."""
    url = "http://127.0.0.1:8080/api/v1/fault"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the telemetry server at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"

    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Response body is not valid JSON. Body: {response.text}")

    expected_data = {"faulty_ip": "10.0.40.55", "log_status": "active"}
    assert data == expected_data, f"Expected JSON payload {expected_data}, got {data}"


def test_log_rotation_and_permissions():
    """Verify that the daemon rotates the log file when it exceeds 500 bytes and sets permissions to 0444."""
    log_dir = "/home/user/net_logs"
    archive_dir = os.path.join(log_dir, "archive")
    log_file = os.path.join(log_dir, "traffic.log")

    os.makedirs(archive_dir, exist_ok=True)
    existing_archives = set(glob.glob(os.path.join(archive_dir, "traffic_*.log")))

    with open(log_file, "w") as f:
        f.write("A" * 600)

    time.sleep(2)

    if os.path.exists(log_file):
        assert os.path.getsize(log_file) <= 500, \
            f"Log file was not rotated, size is still {os.path.getsize(log_file)} bytes"

    current_archives = set(glob.glob(os.path.join(archive_dir, "traffic_*.log")))
    new_archives = current_archives - existing_archives

    assert len(new_archives) >= 1, "No new archive file was created in the archive directory."

    for archive in new_archives:
        file_stat = os.stat(archive)
        permissions = stat.S_IMODE(file_stat.st_mode)
        assert permissions == 0o444, f"Expected permissions 0444 for {archive}, got {oct(permissions)}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
