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
import signal
import socket
import subprocess
import tempfile
import time

import pytest
import requests

TEST_PORTS = {8181, 3131}


def listening_inodes(ports):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10 or fields[3] != "0A":
                        continue
                    port = int(fields[1].rsplit(":", 1)[1], 16)
                    if port in ports:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    return inodes


def listener_pids(ports):
    wanted = {f"socket:[{inode}]" for inode in listening_inodes(ports)}
    pids = set()
    if not wanted:
        return pids
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) in wanted:
                        pids.add(int(entry))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return pids


def stop_existing_services():
    for pid in listener_pids(TEST_PORTS):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    deadline = time.time() + 2
    while time.time() < deadline and listening_inodes(TEST_PORTS):
        time.sleep(0.05)

    for pid in listener_pids(TEST_PORTS):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    deadline = time.time() + 2
    while time.time() < deadline and listening_inodes(TEST_PORTS):
        time.sleep(0.05)
    assert not listening_inodes(TEST_PORTS), "Could not stop pre-existing test services"


def test_start_services_script():
    """Test that start_services.sh exists, is executable, and starts both services."""
    script_path = "/home/user/start_services.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    stop_existing_services()
    account = pwd.getpwnam("user")

    def become_user():
        os.initgroups(account.pw_name, account.pw_gid)
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    subprocess.Popen(
        [script_path],
        cwd=account.pw_dir,
        env={**os.environ, "HOME": account.pw_dir, "USER": account.pw_name, "LOGNAME": account.pw_name},
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        preexec_fn=become_user,
        start_new_session=True,
    )

    deadline = time.time() + 8
    while time.time() < deadline:
        active_ports = set()
        for table in ("/proc/net/tcp", "/proc/net/tcp6"):
            try:
                with open(table) as f:
                    next(f, None)
                    for line in f:
                        fields = line.split()
                        if len(fields) >= 4 and fields[3] == "0A":
                            active_ports.add(int(fields[1].rsplit(":", 1)[1], 16))
            except FileNotFoundError:
                pass
        if TEST_PORTS <= active_ports:
            return
        time.sleep(0.1)
    pytest.fail("start_services.sh did not start listeners on both required ports")


def test_web_service_valid_token():
    """Test the Web Service with the correct Authorization header."""
    url = "http://127.0.0.1:8181/"
    headers = {"Authorization": "Bearer AlphaX9"}
    try:
        response = requests.get(url, headers=headers, timeout=2)
        assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
        assert response.text.strip() == "M1CRO_OK", f"Expected body 'M1CRO_OK', got '{response.text}'"
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to Web Service at {url}: {e}")


def test_web_service_invalid_token():
    """Test the Web Service with an invalid Authorization header."""
    url = "http://127.0.0.1:8181/"
    headers = {"Authorization": "Bearer WrongToken"}
    try:
        response = requests.get(url, headers=headers, timeout=2)
        assert response.status_code == 401, f"Expected HTTP 401 for invalid token, got {response.status_code}"
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to Web Service at {url}: {e}")


def test_web_service_no_token():
    """Test the Web Service with no Authorization header."""
    url = "http://127.0.0.1:8181/"
    try:
        response = requests.get(url, timeout=2)
        assert response.status_code == 401, f"Expected HTTP 401 for missing token, got {response.status_code}"
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to Web Service at {url}: {e}")


def test_mock_ssh_service():
    """Test the Mock SSH Service."""
    host = "127.0.0.1"
    port = 3131
    try:
        with socket.create_connection((host, port), timeout=2) as s:
            data = s.recv(1024)
            assert data == b"SSH-2.0-RejectServer\r\n", f"Expected 'SSH-2.0-RejectServer\\r\\n', got {data}"
            data_after = s.recv(1024)
            assert data_after == b"", "Expected connection to be closed by server, but received more data."
    except Exception as e:
        pytest.fail(f"Failed to verify Mock SSH Service at {host}:{port}: {e}")


def test_git_hook_rejection():
    """Test that the git pre-receive hook rejects commits without 'APPROVED'."""
    repo_path = "/home/user/micro_repo.git"
    assert os.path.isdir(repo_path), f"Git repo {repo_path} does not exist."

    with tempfile.TemporaryDirectory() as tmpdir:
        subprocess.run(["git", "clone", repo_path, tmpdir], check=True, capture_output=True)
        test_file = os.path.join(tmpdir, "test1.txt")
        with open(test_file, "w") as f:
            f.write("test")

        subprocess.run(["git", "add", "test1.txt"], cwd=tmpdir, check=True, capture_output=True)
        subprocess.run([
            "git", "-c", "user.name=Verifier", "-c", "user.email=verifier@example.invalid",
            "-c", "commit.gpgsign=false", "commit", "-m", "Update files"
        ], cwd=tmpdir, check=True, capture_output=True)

        push_result = subprocess.run(["git", "push"], cwd=tmpdir, capture_output=True)
        assert push_result.returncode != 0, "Push succeeded but was expected to fail because commit message lacked 'APPROVED'."


def test_git_hook_acceptance():
    """Test that the git pre-receive hook accepts commits with 'APPROVED'."""
    repo_path = "/home/user/micro_repo.git"
    assert os.path.isdir(repo_path), f"Git repo {repo_path} does not exist."

    with tempfile.TemporaryDirectory() as tmpdir:
        subprocess.run(["git", "clone", repo_path, tmpdir], check=True, capture_output=True)
        test_file = os.path.join(tmpdir, "test2.txt")
        with open(test_file, "w") as f:
            f.write("test")

        subprocess.run(["git", "add", "test2.txt"], cwd=tmpdir, check=True, capture_output=True)
        subprocess.run([
            "git", "-c", "user.name=Verifier", "-c", "user.email=verifier@example.invalid",
            "-c", "commit.gpgsign=false", "commit", "-m", "Update files APPROVED"
        ], cwd=tmpdir, check=True, capture_output=True)

        push_result = subprocess.run(["git", "push"], cwd=tmpdir, capture_output=True, text=True)
        assert push_result.returncode == 0, f"Push failed but was expected to succeed. Output: {push_result.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
