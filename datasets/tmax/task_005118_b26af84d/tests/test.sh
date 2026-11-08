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
import pwd
import re
import stat
import subprocess
import time

import pytest
import requests

VIDEO_PATH = "/app/camera_01.mp4"
SCRIPT_PATH = "/home/user/deploy.sh"
URL = "http://127.0.0.1:9042/api/v1/status"
TOKEN = "Bearer sec-token-8819"
PORT = 9042


def count_black_frames():
    proc = subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-nostats", "-i", VIDEO_PATH,
            "-vf", "blackframe=amount=100:threshold=32",
            "-an", "-f", "null", "-",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert proc.returncode == 0, f"ffmpeg could not analyze the video: {proc.stderr}"
    return len(re.findall(r"\bpblack:100(?:\.0+)?\b", proc.stderr))


def listening_socket_inodes(loopback_only=False):
    inodes = set()
    wanted_port = f"{PORT:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, encoding="ascii") as fh:
                next(fh, None)
                for line in fh:
                    fields = line.split()
                    if len(fields) < 10 or fields[3] != "0A":
                        continue
                    address, port = fields[1].rsplit(":", 1)
                    if port.upper() != wanted_port:
                        continue
                    if loopback_only:
                        if table.endswith("tcp") and address.upper() != "0100007F":
                            continue
                        if table.endswith("tcp6"):
                            continue
                    inodes.add(fields[9])
        except FileNotFoundError:
            pass
    return inodes


def pids_for_inodes(inodes):
    pids = set()
    targets = {f"socket:[{inode}]" for inode in inodes}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(f"{fd_dir}/{fd}") in targets:
                        pids.add(int(name))
                        break
                except (FileNotFoundError, PermissionError, OSError):
                    continue
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return pids


def listener_pids(loopback_only=False):
    return pids_for_inodes(listening_socket_inodes(loopback_only))


def assert_secure_video_state():
    assert os.path.exists(VIDEO_PATH), f"Video file missing at {VIDEO_PATH}"
    st = os.stat(VIDEO_PATH)
    permissions = stat.S_IMODE(st.st_mode)
    assert permissions == 0o600, f"Expected permissions 0o600 (rw-------), but got {oct(permissions)}"
    expected_uid = pwd.getpwnam("user").pw_uid
    assert st.st_uid == expected_uid, "The video must be owned by user"

    acl = subprocess.run(
        ["getfacl", "-cp", VIDEO_PATH],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    ).stdout
    entries = [line.strip() for line in acl.splitlines() if line.strip() and not line.startswith("#")]
    assert "user::rw-" in entries, f"Owner ACL is not rw-: {entries}"
    assert "group::---" in entries, f"Group ACL is not empty: {entries}"
    assert "other::---" in entries, f"Other ACL is not empty: {entries}"
    for entry in entries:
        if entry.startswith("user:") and not entry.startswith("user::"):
            pytest.fail(f"Unexpected named-user ACL grants on video: {entry}")
        if entry.startswith("group:") and not entry.startswith("group::"):
            pytest.fail(f"Unexpected named-group ACL grants on video: {entry}")
        if entry.startswith("mask:"):
            assert entry == "mask::---", f"ACL mask permits access: {entry}"


EXPECTED_BLACK_FRAMES = count_black_frames()


def test_video_permissions():
    assert_secure_video_state()


def test_deploy_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Deployment script missing at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Deployment script {SCRIPT_PATH} is not executable"

    old_pids = listener_pids()
    assert old_pids, "No existing API process was listening on port 9042 before deployment"

    # Deliberately make the video insecure so the deployment script must restore it.
    subprocess.run(["setfacl", "-b", VIDEO_PATH], check=True)
    os.chmod(VIDEO_PATH, 0o644)

    proc = subprocess.Popen(
        [SCRIPT_PATH],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        rc = proc.wait(timeout=12)
    except subprocess.TimeoutExpired:
        proc.kill()
        pytest.fail("Deployment script did not finish after launching the service in the background")
    assert rc == 0, f"Deployment script exited with status {rc}"

    deadline = time.time() + 10
    new_pids = set()
    while time.time() < deadline:
        new_pids = listener_pids(loopback_only=True)
        if new_pids and old_pids.isdisjoint(new_pids):
            break
        time.sleep(0.2)

    assert new_pids, "Deployment script did not launch a service on 127.0.0.1:9042"
    assert old_pids.isdisjoint(new_pids), "Deployment script did not terminate and replace the old port-9042 process"
    assert_secure_video_state()


def test_api_unauthorized():
    try:
        response = requests.get(URL, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API on 127.0.0.1:9042: {e}")
    assert response.status_code == 401, f"Expected HTTP 401 Unauthorized for missing token, got {response.status_code}"


@pytest.mark.parametrize("authorization", [
    "Bearer sec-token-8818",
    "bearer sec-token-8819",
    "Bearer sec-token-8819 ",
    "sec-token-8819",
])
def test_api_rejects_incorrect_authorization(authorization):
    response = requests.get(URL, headers={"Authorization": authorization}, timeout=2)
    assert response.status_code == 401, f"Expected 401 for incorrect Authorization header {authorization!r}, got {response.status_code}"


def test_api_authorized():
    try:
        response = requests.get(URL, headers={"Authorization": TOKEN}, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API on 127.0.0.1:9042: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK for valid token, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("API did not return valid JSON")

    expected = {"status": "ok", "black_frames": EXPECTED_BLACK_FRAMES}
    assert data == expected, f"Expected payload {expected}, got {data}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
