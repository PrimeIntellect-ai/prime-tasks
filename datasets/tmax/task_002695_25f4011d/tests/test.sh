#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import json
import os
import pwd
import re
import shlex
import signal
import subprocess
import time
import urllib.error
import urllib.request

import pytest

HOME = "/home/user"
CONF = f"{HOME}/supervisord.conf"
PIDFILE = f"{HOME}/supervisord.pid"
MONITOR = f"{HOME}/monitor.py"
EXPECTED_USERS = {"groups": {"admin": ["alice"], "monitors": ["bob", "charlie"]}}
EXPECTED_HEALTH = {"status": "ok", "timezone": "America/St_Johns", "locale": "fr_CA.UTF-8"}
EXPECTED_HEALTH_RAW = b'{"status": "ok", "timezone": "America/St_Johns", "locale": "fr_CA.UTF-8"}'


def proc_cmdline(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        return [x.decode(errors="replace") for x in f.read().split(b"\0") if x]


def proc_uid(pid):
    return os.stat(f"/proc/{pid}").st_uid


def proc_ppid(pid):
    with open(f"/proc/{pid}/status") as f:
        for line in f:
            if line.startswith("PPid:"):
                return int(line.split()[1])
    raise AssertionError(f"Cannot determine parent of PID {pid}")


def descendants(root_pid):
    found = set()
    changed = True
    while changed:
        changed = False
        for entry in os.listdir("/proc"):
            if not entry.isdigit():
                continue
            pid = int(entry)
            if pid == root_pid or pid in found:
                continue
            try:
                parent = proc_ppid(pid)
            except (FileNotFoundError, ProcessLookupError, PermissionError):
                continue
            if parent == root_pid or parent in found:
                found.add(pid)
                changed = True
    return found


def read_supervisor_pid():
    assert os.path.exists(PIDFILE), f"{PIDFILE} does not exist"
    try:
        pid = int(open(PIDFILE).read().strip())
    except (ValueError, OSError) as e:
        pytest.fail(f"Invalid supervisord pidfile: {e}")
    assert os.path.isdir(f"/proc/{pid}"), f"supervisord PID {pid} is not running"
    return pid


def monitor_children(supervisor_pid):
    matches = []
    for pid in descendants(supervisor_pid):
        try:
            cmd = proc_cmdline(pid)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
        if len(cmd) == 2 and os.path.basename(cmd[0]) in ("python3", "python3.11") and cmd[1] == MONITOR:
            matches.append(pid)
    return matches


def assert_supervised_state():
    supervisor_pid = read_supervisor_pid()
    cmd = proc_cmdline(supervisor_pid)
    assert any("supervisord" in os.path.basename(arg) for arg in cmd), \
        f"PID {supervisor_pid} is not supervisord: {cmd}"
    assert CONF in cmd or any(arg == f"-c{CONF}" for arg in cmd), \
        f"supervisord was not started with {CONF}: {cmd}"

    user_uid = pwd.getpwnam("user").pw_uid
    assert proc_uid(supervisor_pid) == user_uid, "supervisord is not running as the unprivileged user"

    configured_supervisors = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            candidate = proc_cmdline(int(entry))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
        if any("supervisord" in os.path.basename(x) for x in candidate) and \
                (CONF in candidate or any(x == f"-c{CONF}" for x in candidate)):
            configured_supervisors.append(int(entry))
    assert configured_supervisors == [supervisor_pid], \
        f"Expected exactly one supervisord using the requested config, found {configured_supervisors}"

    children = monitor_children(supervisor_pid)
    assert len(children) == 1, f"Expected exactly one supervised health_monitor, found {children}"
    child = children[0]
    assert proc_uid(child) == user_uid, "monitor.py is not owned by the unprivileged user"

    environ = open(f"/proc/{child}/environ", "rb").read().split(b"\0")
    env = dict(item.decode(errors="replace").split("=", 1) for item in environ if b"=" in item)
    assert env.get("TZ") == "America/St_Johns"
    assert env.get("LANG") == "fr_CA.UTF-8"
    return supervisor_pid, child


def listener_inodes():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local_address, state = fields[1], fields[3]
            address, port = local_address.rsplit(":", 1)
            if state != "0A" or int(port, 16) != 8443:
                continue
            if table.endswith("tcp") and address != "0100007F":
                continue
            inodes.add(fields[9])
    return inodes


def assert_monitor_owns_listener(pid):
    listening = listener_inodes()
    assert listening, "Nothing is listening on port 8443"
    owned = set()
    for fd in os.listdir(f"/proc/{pid}/fd"):
        try:
            target = os.readlink(f"/proc/{pid}/fd/{fd}")
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            owned.add(match.group(1))
    assert listening & owned, "Port 8443 is not owned by the monitor.py process managed by supervisord"


def fetch(path):
    with urllib.request.urlopen(f"http://127.0.0.1:8443{path}", timeout=5) as response:
        return response.status, response.read()


def test_service_running():
    """Preserve the original process checks and verify real supervisor ownership."""
    try:
        output = subprocess.check_output(["pgrep", "-f", "supervisord"], text=True)
        assert output.strip(), "supervisord is not running"
    except subprocess.CalledProcessError:
        pytest.fail("supervisord is not running")

    try:
        output = subprocess.check_output(["pgrep", "-f", "monitor.py"], text=True)
        assert output.strip(), "monitor.py is not running"
    except subprocess.CalledProcessError:
        pytest.fail("monitor.py is not running")

    _, child = assert_supervised_state()
    assert_monitor_owns_listener(child)


def test_idempotency():
    """Run deployment repeatedly and ensure it retains one working supervised instance."""
    script_path = f"{HOME}/deploy_monitor.sh"
    assert os.path.exists(script_path), f"{script_path} does not exist"
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable"

    initial_supervisor, _ = assert_supervised_state()
    for run_number in (2, 3):
        result = subprocess.run([script_path], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, \
            f"deploy_monitor.sh failed on run {run_number}. Output: {result.stderr}"
        supervisor, child = assert_supervised_state()
        assert supervisor == initial_supervisor, "Idempotent rerun replaced or duplicated supervisord"
        assert_monitor_owns_listener(child)
        status, body = fetch("/health")
        assert status == 200
        assert json.loads(body) == EXPECTED_HEALTH


def test_users_json_content():
    users_file = f"{HOME}/config/users.json"
    assert os.path.exists(users_file), f"{users_file} does not exist"
    with open(users_file) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{users_file} is not valid JSON")
    assert data == EXPECTED_USERS, f"Content of {users_file} does not match expected structure"


def test_health_endpoint():
    try:
        status, body = fetch("/health")
        assert status == 200, f"/health returned status {status}"
        data = json.loads(body.decode())
    except Exception as e:
        pytest.fail(f"Failed to access /health endpoint: {e}")
    assert data == EXPECTED_HEALTH, f"/health endpoint returned unexpected data: {data}"
    assert body == EXPECTED_HEALTH_RAW, "/health response body is not in the required exact format"
    _, child = assert_supervised_state()
    assert_monitor_owns_listener(child)


def test_users_endpoint():
    users_file = f"{HOME}/config/users.json"
    expected_raw = open(users_file, "rb").read()
    try:
        status, body = fetch("/users")
        assert status == 200, f"/users returned status {status}"
        data = json.loads(body.decode())
    except Exception as e:
        pytest.fail(f"Failed to access /users endpoint: {e}")
    assert data == EXPECTED_USERS, f"/users endpoint returned unexpected data: {data}"
    assert body == expected_raw, "/users did not return the raw contents of users.json"

    backup = users_file + ".verifier-backup"
    os.replace(users_file, backup)
    try:
        with pytest.raises(urllib.error.HTTPError) as exc:
            fetch("/users")
        assert exc.value.code == 404, f"Missing users.json returned {exc.value.code}, not 404"
    finally:
        os.replace(backup, users_file)


def test_health_result_log():
    log_file = f"{HOME}/health_result.log"
    assert os.path.exists(log_file), f"{log_file} does not exist"
    content = open(log_file, "rb").read()
    try:
        data = json.loads(content.decode())
    except json.JSONDecodeError:
        pytest.fail(f"{log_file} does not contain valid JSON")
    assert data == EXPECTED_HEALTH, f"Content of {log_file} does not match expected structure"
    assert content == EXPECTED_HEALTH_RAW, "health_result.log is not the exact /health response body"


def test_supervisor_config():
    assert os.path.exists(CONF), f"{CONF} does not exist"
    content = open(CONF).read()
    lowered = content.lower()
    assert "autorestart" in lowered, "autorestart policy not found in supervisord.conf"
    assert "environment" in lowered, "environment variables not found in supervisord.conf"
    assert "america/st_johns" in lowered, "TZ environment variable not set correctly in supervisord.conf"
    assert "fr_ca.utf-8" in lowered, "LANG environment variable not set correctly in supervisord.conf"

    parser = configparser.RawConfigParser(strict=False)
    parser.read(CONF)
    assert parser.has_section("supervisord"), "Missing [supervisord] section"
    assert parser.has_section("program:health_monitor"), "Missing [program:health_monitor] section"
    assert parser.get("supervisord", "pidfile", fallback="").strip() == PIDFILE
    assert parser.get("supervisord", "logfile", fallback="").strip() == f"{HOME}/supervisord.log"

    program = "program:health_monitor"
    command = shlex.split(parser.get(program, "command", fallback=""))
    assert len(command) == 2 and os.path.basename(command[0]) == "python3" and command[1] == MONITOR, \
        f"Incorrect health_monitor command: {command}"
    assert parser.get(program, "autorestart", fallback="").strip().lower() == "true"

    lexer = shlex.shlex(parser.get(program, "environment", fallback=""), posix=True)
    lexer.whitespace = ","
    lexer.whitespace_split = True
    env = {}
    for item in lexer:
        if "=" in item:
            key, value = item.strip().split("=", 1)
            env[key] = value
    assert env.get("TZ") == "America/St_Johns"
    assert env.get("LANG") == "fr_CA.UTF-8"


def test_supervisor_restart_behavior():
    supervisor, old_child = assert_supervised_state()
    os.kill(old_child, signal.SIGKILL)
    deadline = time.time() + 20
    new_child = None
    while time.time() < deadline:
        children = monitor_children(supervisor)
        if len(children) == 1 and children[0] != old_child:
            try:
                status, body = fetch("/health")
                if status == 200 and json.loads(body) == EXPECTED_HEALTH:
                    new_child = children[0]
                    break
            except Exception:
                pass
        time.sleep(0.25)
    assert new_child is not None, "supervisord did not restart health_monitor after it was killed"
    assert_monitor_owns_listener(new_child)
    assert_supervised_state()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
