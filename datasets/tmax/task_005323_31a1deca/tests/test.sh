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
import pwd
import secrets
import signal
import socket
import subprocess
import tarfile
import tempfile
import time

import pytest
import requests

SCRIPT = "/home/user/run_all.sh"
BACKUP = "/home/user/backups/app_backup.tar.gz"
CONFIG = "/home/user/app/config.json"
DATABASE = "/home/user/app/data.db"
CONFIG_BYTES = b'{"db_port": 6055, "api_port": 5001}\n'
EXPECTED_DB_BYTES = None
RUN_PROCESS = None


def socket_rows(states=None):
    rows = []
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_address, remote_address, state, inode = fields[1], fields[2], fields[3], fields[9]
                    if states is not None and state not in states:
                        continue
                    local_ip, local_port = local_address.rsplit(":", 1)
                    remote_ip, remote_port = remote_address.rsplit(":", 1)
                    rows.append({
                        "table": table,
                        "local_ip": local_ip,
                        "local_port": int(local_port, 16),
                        "remote_ip": remote_ip,
                        "remote_port": int(remote_port, 16),
                        "state": state,
                        "inode": inode,
                    })
        except FileNotFoundError:
            pass
    return rows


def inode_owners():
    owners = {}
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
                if target.startswith("socket:[") and target.endswith("]"):
                    inode = target[8:-1]
                    owners.setdefault(inode, set()).add(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return owners


def listener_pids(port):
    owners = inode_owners()
    result = set()
    for row in socket_rows({"0A"}):
        if row["local_port"] == port:
            result.update(owners.get(row["inode"], set()))
    return result


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return ""


def kill_port_users(ports):
    victims = set()
    for port in ports:
        victims.update(listener_pids(port))
    for pid in victims:
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    deadline = time.time() + 5
    while time.time() < deadline:
        if not any(listener_pids(port) for port in ports):
            return
        time.sleep(0.1)
    assert not any(listener_pids(port) for port in ports), "Could not clear pre-existing service listeners"


def wait_for_listeners(ports, timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if RUN_PROCESS.poll() not in (None, 0):
            pytest.fail(f"{SCRIPT} exited with status {RUN_PROCESS.returncode}")
        if all(listener_pids(port) for port in ports):
            return
        time.sleep(0.2)
    missing = [port for port in ports if not listener_pids(port)]
    pytest.fail(f"Listeners did not start after executing {SCRIPT}; missing ports: {missing}")


def assert_process_for_listener(port, executable_name, script_name):
    pids = listener_pids(port)
    assert pids, f"No listener found on required backend port {port}"
    commands = [cmdline(pid) for pid in pids]
    assert any(executable_name in command and script_name in command for command in commands), \
        f"Port {port} is not served by the required service {script_name}. Commands: {commands}"


def assert_forwarding_connection(external_port, backend_port, payload):
    with socket.create_connection(("127.0.0.1", external_port), timeout=5) as client:
        client.sendall(payload)
        deadline = time.time() + 3
        while time.time() < deadline:
            owners = inode_owners()
            per_pid = {}
            for row in socket_rows({"01"}):
                for pid in owners.get(row["inode"], set()):
                    per_pid.setdefault(pid, []).append(row)
            for rows in per_pid.values():
                has_external = any(r["local_port"] == external_port or r["remote_port"] == external_port for r in rows)
                has_backend = any(r["local_port"] == backend_port or r["remote_port"] == backend_port for r in rows)
                if has_external and has_backend:
                    return
            time.sleep(0.1)
    pytest.fail(f"No user-space forwarding path from port {external_port} to backend port {backend_port} was observed")


@pytest.fixture(scope="session", autouse=True)
def execute_workflow_from_scratch():
    global EXPECTED_DB_BYTES, RUN_PROCESS

    assert os.path.exists(SCRIPT), f"The script {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a file."
    assert os.access(SCRIPT, os.X_OK), f"The script {SCRIPT} is not executable."
    assert os.path.isfile(BACKUP), f"Backup archive missing at {BACKUP}"

    # Use unpredictable database contents so merely touching or hard-coding the
    # restored files cannot pass; a correct workflow extracts the current archive.
    EXPECTED_DB_BYTES = (json.dumps({
        "records": secrets.randbelow(900000) + 100000,
        "state": "ready",
        "verification_nonce": secrets.token_hex(16),
    }, separators=(",", ":")) + "\n").encode()

    with tempfile.TemporaryDirectory() as temp_dir:
        config_copy = os.path.join(temp_dir, "config.json")
        db_copy = os.path.join(temp_dir, "data.db")
        with open(config_copy, "wb") as f:
            f.write(CONFIG_BYTES)
        with open(db_copy, "wb") as f:
            f.write(EXPECTED_DB_BYTES)
        with tarfile.open(BACKUP, "w:gz") as archive:
            archive.add(config_copy, arcname="config.json")
            archive.add(db_copy, arcname="data.db")
    os.chmod(BACKUP, 0o644)

    kill_port_users({5001, 6055, 9999, 8080, 8081})
    for path in (CONFIG, DATABASE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    account = pwd.getpwnam("user")
    env = os.environ.copy()
    env["HOME"] = account.pw_dir
    env["USER"] = account.pw_name

    def become_user():
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    RUN_PROCESS = subprocess.Popen(
        [SCRIPT],
        cwd=account.pw_dir,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
        preexec_fn=become_user,
    )
    wait_for_listeners({5001, 6055, 8080, 8081})
    yield


def test_run_all_script_exists_and_executable():
    script_path = "/home/user/run_all.sh"
    assert os.path.exists(script_path), f"The script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."


def test_extracted_files_exist():
    config_path = "/home/user/app/config.json"
    db_path = "/home/user/app/data.db"

    assert os.path.exists(config_path), f"Configuration file missing at {config_path}. Was the backup extracted?"
    assert os.path.exists(db_path), f"Database file missing at {db_path}. Was the backup extracted?"
    with open(config_path, "rb") as f:
        assert f.read() == CONFIG_BYTES, "config.json was not restored from the backup"
    with open(db_path, "rb") as f:
        assert f.read() == EXPECTED_DB_BYTES, "data.db was not restored from the current backup archive"


def test_required_backend_services_are_running():
    assert_process_for_listener(5001, "python", "/home/user/app/api.py")
    assert_process_for_listener(6055, "node", "/home/user/app/data_service.js")


def test_external_listeners_are_wildcard_bound_and_forwarded():
    listeners = socket_rows({"0A"})
    for port in (8080, 8081):
        matching = [row for row in listeners if row["local_port"] == port]
        assert matching, f"No external listener on port {port}"
        assert any(row["table"] == "/proc/net/tcp" and row["local_ip"] == "00000000" for row in matching), \
            f"Port {port} is not listening on 0.0.0.0"

    assert_forwarding_connection(8080, 5001, b"GET /api/status HTTP/1.1\r\nHost: localhost\r\n")
    assert_forwarding_connection(8081, 6055, b"VERIFIER_HOLD_CONNECTION\n")


def test_http_api_status():
    url = "http://127.0.0.1:8080/api/status"
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP API at {url}. Error: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, but got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response from {url}, but got: {response.text}")

    assert data.get("status") == "ok", f"Expected 'status' to be 'ok', got: {data.get('status')}"
    assert data.get("db_connected") is True, f"Expected 'db_connected' to be True, got: {data.get('db_connected')}"


def test_tcp_data_service():
    host = "127.0.0.1"
    port = 8081
    try:
        with socket.create_connection((host, port), timeout=5) as s:
            s.sendall(b"PING\n")
            data = s.recv(1024)
    except Exception as e:
        pytest.fail(f"Failed to connect and communicate with the TCP data service at {host}:{port}. Error: {e}")

    response_text = data.decode("utf-8", errors="replace")
    expected_response = "PONG: DATA_READY"
    assert expected_response in response_text, f"Expected TCP response to contain '{expected_response}', but got: {response_text.strip()}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
