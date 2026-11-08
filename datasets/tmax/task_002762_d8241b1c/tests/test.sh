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
import os
import pwd
import shlex
import socket
import subprocess
import time

import pytest
import requests

SERVICE_FILE = "/home/user/.config/systemd/user/voicemail-api.service"
SERVER_SCRIPT = "/home/user/app/server.py"
EXPECTED_TRANSCRIPT = "Authorization code delta seven nine omega."


def systemctl_show(prop):
    uid = pwd.getpwnam("user").pw_uid
    env = (
        f"XDG_RUNTIME_DIR=/run/user/{uid}",
        f"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus",
        "HOME=/home/user",
    )
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "env", *env,
         "systemctl", "--user", "show", "voicemail-api.service",
         f"--property={prop}", "--value"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def socket_table():
    rows = []
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        with open(path) as f:
            next(f)
            for line in f:
                fields = line.split()
                local_hex, remote_hex, state, inode = fields[1], fields[2], fields[3], fields[9]
                local_port = int(local_hex.rsplit(":", 1)[1], 16)
                remote_port = int(remote_hex.rsplit(":", 1)[1], 16)
                rows.append((local_port, remote_port, state, inode))
    return rows


def pid_socket_inodes(pid):
    inodes = set()
    fd_dir = f"/proc/{pid}/fd"
    try:
        names = os.listdir(fd_dir)
    except OSError:
        return inodes
    for name in names:
        try:
            target = os.readlink(os.path.join(fd_dir, name))
        except OSError:
            continue
        if target.startswith("socket:[") and target.endswith("]"):
            inodes.add(target[8:-1])
    return inodes


def listener_pids(port):
    listening = {inode for local, remote, state, inode in socket_table()
                 if local == port and state == "0A"}
    owners = set()
    for entry in os.listdir("/proc"):
        if entry.isdigit() and pid_socket_inodes(entry) & listening:
            owners.add(int(entry))
    return owners


def assert_api_response(response):
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert data.get("transcript") == EXPECTED_TRANSCRIPT, f"Incorrect transcript: {data.get('transcript')}"
    assert data.get("tz") == "Europe/Zurich", f"Incorrect timezone: {data.get('tz')}"
    assert data.get("locale") == "fr_CH.UTF-8", f"Incorrect locale: {data.get('locale')}"


def test_service_file_updated():
    assert os.path.isfile(SERVICE_FILE), f"Service file missing at {SERVICE_FILE}"
    with open(SERVICE_FILE) as f:
        content = f.read()
    assert "Europe/Zurich" in content, "Timezone Europe/Zurich not found in service file"
    assert "fr_CH.UTF-8" in content, "Locale fr_CH.UTF-8 not found in service file"


def test_server_script_updated():
    assert os.path.isfile(SERVER_SCRIPT), f"Server script missing at {SERVER_SCRIPT}"
    with open(SERVER_SCRIPT) as f:
        content = f.read()
    assert EXPECTED_TRANSCRIPT in content, "Transcript text not updated in server.py"

    tree = ast.parse(content, filename=SERVER_SCRIPT)
    assignments = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if any(isinstance(t, ast.Name) and t.id == "TRANSCRIPT_TEXT" for t in targets):
                try:
                    assignments.append(ast.literal_eval(node.value))
                except (ValueError, TypeError):
                    pass
    assert EXPECTED_TRANSCRIPT in assignments, "TRANSCRIPT_TEXT is not assigned the exact transcription"


def test_service_is_actually_running_under_user_systemd():
    assert systemctl_show("LoadState") == "loaded", "voicemail-api.service is not loaded"
    assert systemctl_show("ActiveState") == "active", "voicemail-api.service is not active"
    assert systemctl_show("SubState") == "running", "voicemail-api.service is not running"
    assert systemctl_show("FragmentPath") == SERVICE_FILE, "systemd is not using the required service file"
    assert systemctl_show("WorkingDirectory") == "/home/user/app", "Incorrect systemd WorkingDirectory"

    exec_start = systemctl_show("ExecStart")
    assert "/usr/bin/python3" in exec_start and SERVER_SCRIPT in exec_start, "Incorrect functional ExecStart"

    environment = set(shlex.split(systemctl_show("Environment")))
    assert "TZ=Europe/Zurich" in environment, "Running systemd unit does not inject TZ=Europe/Zurich"
    assert "LANG=fr_CH.UTF-8" in environment, "Running systemd unit does not inject LANG=fr_CH.UTF-8"

    main_pid_text = systemctl_show("MainPID")
    assert main_pid_text.isdigit() and int(main_pid_text) > 0, "Service has no MainPID"
    main_pid = int(main_pid_text)
    with open(f"/proc/{main_pid}/cmdline", "rb") as f:
        argv = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
    assert SERVER_SCRIPT in argv, "The systemd MainPID is not executing server.py"

    assert main_pid in listener_pids(8080), "The systemd service MainPID does not own the HTTP listener on 8080"
    assert main_pid in listener_pids(50051), "The systemd service MainPID does not own the gRPC listener on 50051"


def test_grpc_port_listening():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    result = sock.connect_ex(("127.0.0.1", 50051))
    sock.close()
    assert result == 0, "gRPC port 50051 is not listening. Is the service running?"


def test_port_9090_is_a_real_ssh_forward_to_8080():
    owners = listener_pids(9090)
    assert owners, "Nothing is listening on port 9090"

    ssh_pids = []
    for pid in owners:
        try:
            executable = os.path.realpath(f"/proc/{pid}/exe")
        except OSError:
            continue
        if executable == "/usr/bin/ssh":
            ssh_pids.append(pid)
    assert ssh_pids, "Port 9090 is not owned by the OpenSSH client"

    probe = socket.create_connection(("127.0.0.1", 9090), timeout=3)
    try:
        probe.sendall(b"GET /transcript HTTP/1.1\r\nHost: localhost\r\n")
        deadline = time.time() + 3
        forwarded = False
        while time.time() < deadline and not forwarded:
            table = socket_table()
            for pid in ssh_pids:
                inodes = pid_socket_inodes(pid)
                if any(remote == 8080 and state == "01" and inode in inodes
                       for local, remote, state, inode in table):
                    forwarded = True
                    break
            if not forwarded:
                time.sleep(0.1)
        assert forwarded, "The SSH listener on 9090 did not establish a forward to port 8080"
    finally:
        probe.close()
    time.sleep(0.2)


def test_http_endpoint_via_ssh_tunnel():
    headers = {"Authorization": "Bearer voicemail-admin"}

    direct = requests.get("http://127.0.0.1:8080/transcript", headers=headers, timeout=5)
    assert_api_response(direct)

    unauthorized = requests.get("http://127.0.0.1:9090/transcript", timeout=5)
    assert unauthorized.status_code == 401, "Tunnelled endpoint does not enforce authorization"

    try:
        response = requests.get("http://127.0.0.1:9090/transcript", headers=headers, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to http://127.0.0.1:9090. Is the SSH tunnel active?")
    except requests.exceptions.Timeout:
        pytest.fail("Request to http://127.0.0.1:9090 timed out.")
    assert_api_response(response)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
