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
import os
import re
import socket
import subprocess
import time

import pytest
import requests

ROOT = "/app/net-bridge-c"
GATEWAY = ROOT + "/gateway"
PID_FILE = "/home/user/gw/run/gw.pid"
LOG_FILE = "/home/user/gw/logs/gw.log"


def read_pid():
    with open(PID_FILE, "r") as f:
        value = f.read().strip()
    assert value.isdigit(), f"PID file contains invalid PID: {value}"
    return int(value)


def process_environment(pid):
    with open(f"/proc/{pid}/environ", "rb") as f:
        entries = f.read().split(b"\0")
    result = {}
    for entry in entries:
        if b"=" in entry:
            key, value = entry.split(b"=", 1)
            result[key.decode(errors="replace")] = value.decode(errors="replace")
    return result


def listening_socket_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        with open(table, "r") as f:
            next(f)
            for line in f:
                fields = line.split()
                local_port = int(fields[1].rsplit(":", 1)[1], 16)
                state = fields[3]
                if local_port == port and state == "0A":
                    result.add(fields[9])
    return result


def pid_socket_inodes(pid):
    result = set()
    for fd in glob.glob(f"/proc/{pid}/fd/*"):
        try:
            target = os.readlink(fd)
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            result.add(match.group(1))
    return result


def assert_gateway_process(pid, allow_deleted=False):
    assert os.path.exists(f"/proc/{pid}"), f"PID {pid} is not alive"
    exe = os.readlink(f"/proc/{pid}/exe")
    if allow_deleted and exe.endswith(" (deleted)"):
        exe = exe[:-10]
    assert exe == GATEWAY, f"PID {pid} is not the gateway executable: {exe}"

    env = process_environment(pid)
    assert env.get("BIND_PORT") == "8888", "Gateway was not started with BIND_PORT=8888"
    assert env.get("CONFIG_PATH") == "/home/user/gw/active_conf", "Gateway was not started with the required CONFIG_PATH"

    listeners = listening_socket_inodes(8888)
    assert listeners & pid_socket_inodes(pid), f"PID {pid} does not own the listener on port 8888"

    assert os.path.samefile(f"/proc/{pid}/fd/1", LOG_FILE), "Gateway stdout is not redirected to gw.log"
    assert os.path.samefile(f"/proc/{pid}/fd/2", LOG_FILE), "Gateway stderr is not redirected to gw.log"

    ancestor = pid
    found_supervisor = False
    for _ in range(8):
        with open(f"/proc/{ancestor}/status", "r") as f:
            status = f.read()
        match = re.search(r"^PPid:\s+(\d+)$", status, re.MULTILINE)
        if not match or match.group(1) == "0":
            break
        ancestor = int(match.group(1))
        try:
            with open(f"/proc/{ancestor}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
        except OSError:
            break
        if "/home/user/supervisor.sh" in cmdline:
            found_supervisor = True
            break
    assert found_supervisor, f"Gateway PID {pid} is not managed by /home/user/supervisor.sh"


def backup_state():
    result = {}
    for path in glob.glob("/home/user/gw/logs/gw.log.bak.*"):
        try:
            st = os.stat(path)
            result[path] = (st.st_mtime_ns, st.st_size)
        except FileNotFoundError:
            pass
    return result


def test_directory_structure():
    assert os.path.isdir("/home/user/gw/logs"), "/home/user/gw/logs does not exist"
    assert os.path.isdir("/home/user/gw/conf"), "/home/user/gw/conf does not exist"
    assert os.path.isdir("/home/user/gw/run"), "/home/user/gw/run does not exist"


def test_configuration_file():
    conf_path = "/home/user/gw/conf/settings.ini"
    assert os.path.isfile(conf_path), f"{conf_path} does not exist"
    with open(conf_path, "r") as f:
        content = f.read().strip()
    assert content == "target=127.0.0.1:9090", f"Configuration file content is incorrect: {content}"


def test_symlink():
    symlink_path = "/home/user/gw/active_conf"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink"
    assert os.readlink(symlink_path) == "/home/user/gw/conf/settings.ini", f"Symlink points to wrong location: {os.readlink(symlink_path)}"


def test_supervisor_script_exists():
    script_path = "/home/user/supervisor.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist"
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable"
    with open(script_path, "rb") as f:
        first_line = f.readline().decode(errors="replace")
    assert first_line.startswith("#!") and "bash" in first_line, "supervisor.sh is not a bash script"


def test_source_and_makefile_are_fixed_and_build_gateway():
    source_path = ROOT + "/src/gateway.c"
    makefile_path = ROOT + "/Makefile"
    assert os.path.isfile(source_path), f"Missing source file: {source_path}"
    assert os.path.isfile(makefile_path), f"Missing Makefile: {makefile_path}"

    with open(source_path, "r") as f:
        source = f.read()
    code_without_comments = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    code_without_comments = re.sub(r"//.*", "", code_without_comments)
    assert re.search(r'getenv\s*\(\s*"BIND_PORT"\s*\)', code_without_comments), "gateway.c does not read BIND_PORT with getenv()"
    assert re.search(r"\batoi\s*\(", code_without_comments), "gateway.c does not convert BIND_PORT with atoi()"

    dry_run = subprocess.run(["make", "-B", "-n"], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert dry_run.returncode == 0, f"Makefile dry run failed:\n{dry_run.stdout}"
    assert re.search(r"(?:^|\s)(?:-pthread|-lpthread)(?:\s|$)", dry_run.stdout), f"Makefile compile/link command lacks a pthread flag:\n{dry_run.stdout}"

    if os.path.lexists(GATEWAY):
        os.unlink(GATEWAY)
    build = subprocess.run(["make", "-B"], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert build.returncode == 0, f"make failed:\n{build.stdout}"
    assert os.path.isfile(GATEWAY), f"Gateway executable not found at {GATEWAY}. Did compilation fail?"
    assert os.access(GATEWAY, os.X_OK), f"{GATEWAY} is not executable"


def test_gateway_executable_exists():
    exe_path = "/app/net-bridge-c/gateway"
    assert os.path.isfile(exe_path), f"Gateway executable not found at {exe_path}. Did compilation fail?"
    assert os.access(exe_path, os.X_OK), f"{exe_path} is not executable"


def test_compiled_gateway_honors_bind_port_and_crashes():
    probe = socket.socket()
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
    probe.close()

    env = os.environ.copy()
    env["BIND_PORT"] = str(port)
    env["CONFIG_PATH"] = "/home/user/gw/active_conf"
    proc = subprocess.Popen([GATEWAY], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        ping_url = f"http://127.0.0.1:{port}/ping"
        deadline = time.time() + 3
        response = None
        while time.time() < deadline:
            assert proc.poll() is None, "Freshly built gateway exited before accepting connections"
            try:
                response = requests.get(ping_url, timeout=0.25)
                break
            except requests.RequestException:
                time.sleep(0.05)
        assert response is not None, f"Freshly built gateway did not listen on BIND_PORT={port}"
        assert response.status_code == 200
        assert "PONG" in response.text

        try:
            requests.get(f"http://127.0.0.1:{port}/crash", timeout=1)
        except requests.RequestException:
            pass
        deadline = time.time() + 2
        while proc.poll() is None and time.time() < deadline:
            time.sleep(0.05)
        assert proc.poll() is not None, "GET /crash did not terminate the gateway process"
        assert proc.returncode != 0, "Gateway crash endpoint exited successfully instead of crashing"
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()


def test_service_running_and_supervisor_behavior():
    url_ping = "http://127.0.0.1:8888/ping"
    url_crash = "http://127.0.0.1:8888/crash"

    try:
        resp = requests.get(url_ping, timeout=2)
        assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}"
        assert "PONG" in resp.text, f"Expected PONG in response, got: {resp.text}"
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to gateway at {url_ping}: {e}")

    old_pid = read_pid()
    assert_gateway_process(old_pid, allow_deleted=True)
    before_backups = backup_state()

    try:
        requests.get(url_crash, timeout=2)
    except requests.RequestException:
        pass

    time.sleep(2)

    assert not os.path.exists(f"/proc/{old_pid}"), f"GET /crash did not terminate gateway PID {old_pid}"
    new_pid = read_pid()
    assert new_pid != old_pid, "Supervisor did not replace the crashed gateway process"
    assert_gateway_process(new_pid)

    try:
        resp = requests.get(url_ping, timeout=2)
        assert resp.status_code == 200, f"Expected 200 OK after crash recovery, got {resp.status_code}"
        assert "PONG" in resp.text, f"Expected PONG in response after crash recovery, got: {resp.text}"
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to gateway after crash at {url_ping}. Supervisor did not restart it properly: {e}")

    backup_logs = glob.glob("/home/user/gw/logs/gw.log.bak.*")
    assert len(backup_logs) > 0, "No backup log files found matching /home/user/gw/logs/gw.log.bak.* after crash"
    after_backups = backup_state()
    fresh = [path for path, state in after_backups.items() if path not in before_backups or before_backups[path] != state]
    assert fresh, "The crash did not create or update a backup log; only pre-existing backups were found"
    assert any(re.fullmatch(r"/home/user/gw/logs/gw\.log\.bak\.\d+", path) for path in fresh), "Fresh backup log does not use a Unix-epoch timestamp suffix"


def test_pid_file_exists():
    pid_path = "/home/user/gw/run/gw.pid"
    assert os.path.isfile(pid_path), f"PID file {pid_path} does not exist"
    with open(pid_path, "r") as f:
        pid = f.read().strip()
    assert pid.isdigit(), f"PID file contains invalid PID: {pid}"
    assert os.path.exists(f"/proc/{pid}"), f"PID file refers to non-running process {pid}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
