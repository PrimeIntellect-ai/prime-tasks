#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import subprocess
import sys
import time
import urllib.request


def test_watchdog_log_exists_and_content():
    log_path = "/home/user/logs/watchdog.log"
    assert os.path.exists(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) >= 2, f"Log file {log_path} must contain at least two lines."

    ok_regex = re.compile(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] STATUS: OK$")
    restarted_regex = re.compile(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] STATUS: RESTARTED$")

    has_ok = any(ok_regex.match(line) for line in lines)
    has_restarted = any(restarted_regex.match(line) for line in lines)

    assert has_ok, "Log file missing 'STATUS: OK' line matching the required format."
    assert has_restarted, "Log file missing 'STATUS: RESTARTED' line matching the required format."


def test_app_health_endpoint():
    url = "http://127.0.0.1:8080/health"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=2) as response:
            status = response.getcode()
            body = response.read().decode("utf-8").strip()
    except Exception as e:
        assert False, f"Failed to connect to {url}: {e}"

    assert status == 200, f"Expected HTTP 200 from {url}, got {status}."
    assert body == "OK", f"Expected response body 'OK' from {url}, got '{body}'."


def test_pid_file_exists_and_accurate():
    pid_file = "/home/user/app/app.pid"
    assert os.path.exists(pid_file), f"PID file {pid_file} does not exist."

    with open(pid_file, "r") as f:
        pid_str = f.read().strip()

    assert pid_str.isdigit(), f"PID file {pid_file} does not contain a valid integer."
    pid = int(pid_str)

    try:
        os.kill(pid, 0)
    except OSError:
        assert False, f"Process with PID {pid} from {pid_file} is not running."


def test_deploy_idempotency():
    pid_file = "/home/user/app/app.pid"
    assert os.path.exists(pid_file), f"PID file {pid_file} does not exist."

    with open(pid_file, "r") as f:
        initial_pid = f.read().strip()

    deploy_script = "/home/user/deploy.py"
    assert os.path.exists(deploy_script), f"Deploy script {deploy_script} does not exist."

    result = subprocess.run(["python3", deploy_script], capture_output=True, text=True)
    assert result.returncode == 0, f"deploy.py failed with return code {result.returncode}."

    with open(pid_file, "r") as f:
        new_pid = f.read().strip()

    assert initial_pid == new_pid, "deploy.py is not idempotent: PID changed after running deploy.py again."


def read_pid():
    with open("/home/user/app/app.pid", "r") as f:
        value = f.read().strip()
    assert value.isdigit(), "app.pid does not contain an integer"
    return int(value)


def pid_runs_app(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            args = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
        cwd = os.readlink(f"/proc/{pid}/cwd")
    except OSError:
        return False
    target = os.path.realpath("/home/user/app/app.py")
    for arg in args:
        if not arg.endswith("app.py"):
            continue
        candidate = arg if os.path.isabs(arg) else os.path.join(cwd, arg)
        if os.path.realpath(candidate) == target:
            return True
    return False


def pid_owns_listener(pid):
    wanted = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                rows = f.read().splitlines()[1:]
        except OSError:
            continue
        for row in rows:
            fields = row.split()
            local, state, inode = fields[1], fields[3], fields[9]
            address, port = local.split(":")
            if state == "0A" and int(port, 16) == 8080:
                if (table.endswith("tcp") and address == "0100007F") or table.endswith("tcp6"):
                    wanted.add(inode)
    try:
        for name in os.listdir(f"/proc/{pid}/fd"):
            try:
                link = os.readlink(f"/proc/{pid}/fd/{name}")
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", link)
            if match and match.group(1) in wanted:
                return True
    except OSError:
        pass
    return False


def wait_for_valid_app(pid, timeout=6):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if pid_runs_app(pid) and pid_owns_listener(pid):
            try:
                with urllib.request.urlopen("http://127.0.0.1:8080/health", timeout=1) as response:
                    if response.status == 200 and response.read().decode().strip() == "OK":
                        return
            except Exception:
                pass
        time.sleep(0.1)
    assert False, f"PID {pid} is not app.py listening on 127.0.0.1:8080 with a working /health endpoint"


def stop_and_wait(pid):
    try:
        os.kill(pid, 15)
    except ProcessLookupError:
        return
    deadline = time.time() + 6
    while time.time() < deadline:
        if not os.path.exists(f"/proc/{pid}"):
            return
        try:
            with open(f"/proc/{pid}/stat", "r") as f:
                if f.read().split()[2] == "Z":
                    return
        except OSError:
            return
        time.sleep(0.1)
    os.kill(pid, 9)
    time.sleep(0.2)


def assert_fresh_line(line, status, started, ended):
    match = re.fullmatch(r"\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] STATUS: " + status, line)
    assert match, f"New watchdog line has wrong format or status: {line!r}"
    stamp = datetime.datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S").replace(
        tzinfo=datetime.timezone.utc
    ).timestamp()
    assert started - 2 <= stamp <= ended + 2, "Watchdog timestamp is not the current UTC time"


def test_real_deploy_and_watchdog_behavior():
    app = "/home/user/app/app.py"
    deploy = "/home/user/deploy.py"
    watchdog = "/home/user/watchdog.py"
    log = "/home/user/logs/watchdog.log"
    for path in (app, deploy, watchdog):
        assert os.path.isfile(path), f"Required Python file {path} is missing"
        result = subprocess.run(
            [sys.executable, "-m", "py_compile", path], capture_output=True, text=True
        )
        assert result.returncode == 0, f"{path} is not valid Python: {result.stderr}"

    initial_pid = read_pid()
    wait_for_valid_app(initial_pid)

    with open(log, "r") as f:
        before = f.read().splitlines()
    started = time.time()
    result = subprocess.run([sys.executable, watchdog], capture_output=True, text=True, timeout=10)
    ended = time.time()
    assert result.returncode == 0, f"watchdog.py failed on a healthy app: {result.stderr}"
    with open(log, "r") as f:
        after = f.read().splitlines()
    assert after[:len(before)] == before and len(after) == len(before) + 1, "Healthy watchdog run must append one log line"
    assert_fresh_line(after[-1], "OK", started, ended)
    assert read_pid() == initial_pid, "Healthy watchdog run unexpectedly replaced the app"

    stop_and_wait(initial_pid)

    marker = "/tmp/watchdog_called_deploy"
    backup = "/home/user/deploy.py.verifier_original"
    if os.path.exists(marker):
        os.unlink(marker)
    assert not os.path.exists(backup), f"Unexpected path already exists: {backup}"
    os.replace(deploy, backup)
    wrapper = (
        "import os, sys\n"
        f"with open({marker!r}, 'a') as f: f.write('called\\n')\n"
        f"os.execv(sys.executable, [sys.executable, {backup!r}])\n"
    )
    with open(deploy, "w") as f:
        f.write(wrapper)

    try:
        with open(log, "r") as f:
            before = f.read().splitlines()
        started = time.time()
        result = subprocess.run([sys.executable, watchdog], capture_output=True, text=True, timeout=12)
        ended = time.time()
    finally:
        if os.path.exists(deploy):
            os.unlink(deploy)
        os.replace(backup, deploy)

    assert result.returncode == 0, f"watchdog.py failed while the app was down: {result.stderr}"
    assert os.path.exists(marker) and os.path.getsize(marker) > 0, "watchdog.py did not execute /home/user/deploy.py"
    with open(log, "r") as f:
        after = f.read().splitlines()
    assert after[:len(before)] == before and len(after) == len(before) + 1, "Failed-health watchdog run must append one log line"
    assert_fresh_line(after[-1], "RESTARTED", started, ended)

    restarted_pid = read_pid()
    assert restarted_pid != initial_pid, "Watchdog/deployer did not replace the killed application"
    wait_for_valid_app(restarted_pid)

    stop_and_wait(restarted_pid)
    result = subprocess.run([sys.executable, deploy], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"deploy.py could not independently restart a stopped app: {result.stderr}"
    final_pid = read_pid()
    assert final_pid != restarted_pid, "deploy.py left the stale PID after the application stopped"
    wait_for_valid_app(final_pid)

    result = subprocess.run([sys.executable, deploy], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Second deploy.py invocation failed: {result.stderr}"
    assert read_pid() == final_pid, "deploy.py changed the PID of an already-running application"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
