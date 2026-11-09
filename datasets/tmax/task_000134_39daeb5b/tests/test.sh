#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import shutil
import signal
import socket
import sqlite3
import stat
import subprocess
import time
import urllib.error
import urllib.request
import uuid

HOME = "/home/user"
EXPECTED_USERS = [
    {"username": "alice", "role": "admin"},
    {"username": "bob", "role": "dev"},
    {"username": "charlie", "role": "dev"},
]


def api_pids():
    found = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
            if "python" in cmdline and "api.py" in cmdline:
                found.append(int(pid))
        except (OSError, IOError):
            pass
    return found


def process_alive(pid):
    try:
        with open(f"/proc/{pid}/stat", "r") as f:
            state = f.read().split()[2]
        return state != "Z"
    except (OSError, IndexError):
        return False


def wait_dead(pid, timeout=4):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not process_alive(pid):
            return True
        time.sleep(0.05)
    return not process_alive(pid)


def stop_process(pid):
    if not process_alive(pid):
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    if not wait_dead(pid, 2):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        wait_dead(pid, 2)


def read_api(port, timeout=1):
    req = urllib.request.Request(f"http://127.0.0.1:{port}/users")
    with urllib.request.urlopen(req, timeout=timeout) as response:
        status = response.status
        content_type = response.headers.get("Content-Type", "")
        data = json.loads(response.read().decode("utf-8"))
    return status, content_type, data


def wait_for_api(port, timeout=6):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            return read_api(port)
        except Exception as exc:
            last_error = exc
            time.sleep(0.1)
    raise AssertionError(f"API on port {port} did not become healthy: {last_error}")


def read_tracking():
    with open(f"{HOME}/active_port.txt", "r") as f:
        port = f.read().strip()
    with open(f"{HOME}/active_pid.txt", "r") as f:
        pid_text = f.read().strip()
    assert pid_text.isdigit(), f"Invalid active PID: {pid_text}"
    return port, int(pid_text)


def assert_expected_api(port):
    status, content_type, data = wait_for_api(port)
    assert status == 200
    assert content_type.lower().split(";", 1)[0].strip() == "application/json"
    assert sorted(data, key=lambda x: x["username"]) == EXPECTED_USERS


def test_database_contents():
    db_path = "/home/user/app.db"
    assert os.path.exists(db_path), f"Database file {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT username, role FROM users ORDER BY username;")
        rows = cursor.fetchall()
    except sqlite3.OperationalError as e:
        assert False, f"Failed to query database: {e}"
    finally:
        conn.close()

    expected = [("alice", "admin"), ("bob", "dev"), ("charlie", "dev")]
    assert rows == expected, f"Database contents do not match expected. Got: {rows}"


def test_active_port_file():
    port_file = "/home/user/active_port.txt"
    assert os.path.exists(port_file), f"{port_file} does not exist."
    with open(port_file, "r") as f:
        port = f.read().strip()
    assert port == "8080", f"Expected active port to be 8080, got {port}."


def test_active_pid_file_and_process():
    pid_file = "/home/user/active_pid.txt"
    assert os.path.exists(pid_file), f"{pid_file} does not exist."
    with open(pid_file, "r") as f:
        pid_str = f.read().strip()

    assert pid_str.isdigit(), f"PID file does not contain a valid integer: {pid_str}"
    pid = int(pid_str)

    try:
        os.kill(pid, 0)
    except OSError:
        assert False, f"Process with PID {pid} from active_pid.txt is not running."

    cmdline_file = f"/proc/{pid}/cmdline"
    assert os.path.exists(cmdline_file), f"Process {pid} exists but cannot read cmdline."
    with open(cmdline_file, "r") as f:
        cmdline = f.read().replace('\0', ' ')
    assert "api.py" in cmdline, f"Process {pid} is not api.py. Cmdline: {cmdline}"


def test_api_responds_on_8080():
    url = "http://localhost:8080/users"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req) as response:
            assert response.status == 200, f"Expected status 200, got {response.status}"
            data = json.loads(response.read().decode('utf-8'))
            assert isinstance(data, list), "Expected a JSON array."
            assert len(data) == 3, "Expected 3 users in the response."
    except urllib.error.URLError as e:
        assert False, f"Failed to connect to API on port 8080: {e}"


def test_deployment_test_json():
    json_path = "/home/user/deployment_test.json"
    assert os.path.exists(json_path), f"{json_path} does not exist."
    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{json_path} does not contain valid JSON."

    expected_users = [
        {"username": "alice", "role": "admin"},
        {"username": "bob", "role": "dev"},
        {"username": "charlie", "role": "dev"}
    ]

    data_sorted = sorted(data, key=lambda x: x.get("username", ""))
    expected_sorted = sorted(expected_users, key=lambda x: x.get("username", ""))
    assert data_sorted == expected_sorted, f"JSON contents do not match expected. Got: {data_sorted}"


def test_only_one_api_instance():
    pids = api_pids()
    assert len(pids) == 1, f"Expected exactly one instance of api.py running, found {len(pids)}: {pids}"


def test_required_artifacts_and_behavior():
    manager = f"{HOME}/user_manager.py"
    api = f"{HOME}/api.py"
    deploy = f"{HOME}/deploy.sh"
    db = f"{HOME}/app.db"

    for path in (manager, api, deploy):
        assert os.path.exists(path), f"Required artifact {path} does not exist"
        assert not os.path.islink(path), f"Required artifact {path} must not be a symlink"
        assert stat.S_ISREG(os.stat(path).st_mode), f"Required artifact {path} is not a regular file"

    with open(api, "r") as f:
        tree = ast.parse(f.read(), filename=api)
    uses_http_server = any(
        (isinstance(node, ast.Import) and any(alias.name == "http.server" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "http.server")
        for node in ast.walk(tree)
    )
    assert uses_http_server, "api.py must use Python's standard http.server library"

    with open(deploy, "r", errors="replace") as f:
        first_line = f.readline()
    assert "bash" in first_line, "deploy.sh must be a bash script"

    # Stop the verified final instance so the submitted artifacts can be exercised
    # from a clean state without fixed fixture data.
    for pid in api_pids():
        stop_process(pid)
    assert not api_pids(), "Could not stop the existing API instance"

    backup_db = f"/tmp/app.db.audit.{uuid.uuid4().hex}"
    os.replace(db, backup_db)
    dynamic_api = None
    try:
        suffix = uuid.uuid4().hex
        dynamic_users = [
            (f"user_{suffix}_a", f"role_{suffix}_x"),
            (f"user_{suffix}_b", f"role_{suffix}_y"),
        ]
        for username, role in dynamic_users:
            result = subprocess.run(
                ["python3", manager, "add", username, role],
                cwd=HOME,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, f"user_manager.py failed: {result.stderr}"

        conn = sqlite3.connect(db)
        try:
            columns = [row[1:3] for row in conn.execute("PRAGMA table_info(users)")]
            rows = conn.execute("SELECT username, role FROM users ORDER BY username").fetchall()
        finally:
            conn.close()
        assert columns == [("username", "TEXT"), ("role", "TEXT")], f"Wrong users schema: {columns}"
        assert rows == sorted(dynamic_users), f"user_manager.py did not add requested users: {rows}"

        sock = socket.socket()
        sock.bind(("127.0.0.1", 0))
        random_port = sock.getsockname()[1]
        sock.close()
        dynamic_api = subprocess.Popen(
            ["python3", api, str(random_port)],
            cwd=HOME,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        status, content_type, data = wait_for_api(random_port)
        assert status == 200
        assert content_type.lower().split(";", 1)[0].strip() == "application/json"
        expected_dynamic = [
            {"username": username, "role": role} for username, role in sorted(dynamic_users)
        ]
        assert data == expected_dynamic, f"api.py returned wrong database contents: {data}"
    finally:
        if dynamic_api is not None:
            stop_process(dynamic_api.pid)
        if os.path.exists(db):
            os.remove(db)
        os.replace(backup_db, db)

    # Re-run the required two-stage deployment from its specified initial state.
    for name in ("active_port.txt", "active_pid.txt"):
        path = f"{HOME}/{name}"
        if os.path.exists(path):
            os.remove(path)

    first = subprocess.run(
        ["bash", deploy], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=12
    )
    assert first.returncode == 0, f"First deploy.sh run failed: {first.stdout}\n{first.stderr}"
    first_port, first_pid = read_tracking()
    assert first_port == "8081", f"First deployment selected {first_port}, expected 8081"
    assert process_alive(first_pid), "First deployed API process is not alive"
    assert_expected_api(8081)

    second = subprocess.run(
        ["bash", deploy], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=12
    )
    assert second.returncode == 0, f"Second deploy.sh run failed: {second.stdout}\n{second.stderr}"
    second_port, second_pid = read_tracking()
    assert second_port == "8080", f"Second deployment selected {second_port}, expected 8080"
    assert second_pid != first_pid, "Second deployment did not start a new API process"
    assert process_alive(second_pid), "Second deployed API process is not alive"
    assert wait_dead(first_pid), "Second deployment did not stop the old API process"
    assert_expected_api(8080)
    assert api_pids() == [second_pid], f"Expected only the second API process, found {api_pids()}"

    # A failed candidate must not replace or kill the active deployment.
    api_backup = f"/tmp/api.py.audit.{uuid.uuid4().hex}"
    os.replace(api, api_backup)
    try:
        with open(api, "w") as f:
            f.write("import sys\nsys.exit(1)\n")
        failed = subprocess.run(
            ["bash", deploy], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=12
        )
        assert failed.returncode != 0, "deploy.sh reported success for an unhealthy new instance"
        failed_port, failed_pid = read_tracking()
        assert (failed_port, failed_pid) == ("8080", second_pid), \
            "Failed deployment changed the active tracking files"
        assert process_alive(second_pid), "Failed deployment killed the old active instance"
        assert_expected_api(8080)
    finally:
        if os.path.exists(api):
            os.remove(api)
        os.replace(api_backup, api)

    assert api_pids() == [second_pid], f"Expected exactly one active API after tests, found {api_pids()}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
