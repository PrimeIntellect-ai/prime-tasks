#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import gzip
import json
import os
import pwd
import re
import signal
import stat
import subprocess
import tarfile
import tempfile
import time
import urllib.request

import pytest

PROJECT_DIR = "/home/user/infra_project"
DEPLOY = os.path.join(PROJECT_DIR, "deploy.sh")
SUPERVISOR = os.path.join(PROJECT_DIR, "supervisor.sh")
MONITOR = os.path.join(PROJECT_DIR, "health_monitor.sh")
SERVER = os.path.join(PROJECT_DIR, "server.py")
LOGS = os.path.join(PROJECT_DIR, "logs")
SERVER_LOG = os.path.join(LOGS, "server.log")
HEALTH_LOG = os.path.join(LOGS, "health.log")
USER_UID = pwd.getpwnam("user").pw_uid
STAMP_RE = re.compile(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] Starting server$")


def cmdline(pid):
    try:
        raw = open(f"/proc/{pid}/cmdline", "rb").read()
        return [x.decode(errors="replace") for x in raw.split(b"\0") if x]
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return []


def ppid(pid):
    try:
        for line in open(f"/proc/{pid}/status"):
            if line.startswith("PPid:"):
                return int(line.split()[1])
    except (FileNotFoundError, ProcessLookupError):
        pass
    return 0


def all_pids():
    return [int(x) for x in os.listdir("/proc") if x.isdigit()]


def uid_of(pid):
    return os.stat(f"/proc/{pid}").st_uid


def listener_inodes(port):
    wanted = f"{port:04X}"
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            rows = open(table).read().splitlines()[1:]
        except FileNotFoundError:
            continue
        for row in rows:
            fields = row.split()
            if fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                found.add(fields[9])
    return found


def owners_of_inodes(inodes):
    owners = set()
    if not inodes:
        return owners
    for pid in all_pids():
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                m = re.fullmatch(r"socket:\[(\d+)\]", target)
                if m and m.group(1) in inodes:
                    owners.add(pid)
        except (FileNotFoundError, PermissionError):
            pass
    return owners


def listener_owners(port):
    return owners_of_inodes(listener_inodes(port))


def kill_old_services():
    victims = set(listener_owners(8080)) | set(listener_owners(9090))
    for pid in all_pids():
        text = " ".join(cmdline(pid))
        if any(path in text for path in (SERVER, SUPERVISOR, MONITOR)):
            victims.add(pid)
    for pid in victims:
        if pid not in (os.getpid(), os.getppid()):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    deadline = time.time() + 3
    while time.time() < deadline and (listener_owners(8080) or listener_owners(9090)):
        time.sleep(0.05)


def wait_until(predicate, timeout=8, message="condition not met"):
    deadline = time.time() + timeout
    while time.time() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.05)
    pytest.fail(message)


def server_pids():
    result = []
    for pid in all_pids():
        args = cmdline(pid)
        if SERVER in args and args and os.path.basename(args[0]).startswith("python3"):
            result.append(pid)
    return result


def script_pids(path):
    return [pid for pid in all_pids() if path in cmdline(pid)]


def valid_start_entries():
    try:
        lines = open(SERVER_LOG).read().splitlines()
    except FileNotFoundError:
        return []
    return [(line, STAMP_RE.fullmatch(line)) for line in lines if "Starting server" in line]


def get_url(path, timeout=5):
    with urllib.request.urlopen("http://127.0.0.1:9090" + path, timeout=timeout) as response:
        return response.status, response.read().decode("utf-8")


def is_descendant(pid, ancestor):
    seen = set()
    while pid > 1 and pid not in seen:
        if pid == ancestor:
            return True
        seen.add(pid)
        pid = ppid(pid)
    return False


def test_deploy_script_exists_and_executable():
    assert os.path.isfile(DEPLOY), f"{DEPLOY} does not exist."
    st = os.stat(DEPLOY)
    assert bool(st.st_mode & stat.S_IXUSR), f"{DEPLOY} is not executable."


def test_execution_and_initial_state():
    kill_old_services()
    for path in (os.path.join(PROJECT_DIR, "data"), LOGS):
        subprocess.run(["rm", "-rf", path], check=True)
    for path in (os.path.join(PROJECT_DIR, "logrotate.status"),):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    nonce = f"verifier-{time.time_ns()}"
    backup = os.path.join(PROJECT_DIR, "backup.tar.gz")
    with tempfile.TemporaryDirectory() as td:
        os.makedirs(os.path.join(td, "data"))
        payload = '{"status": "recovered"}\n' + nonce + "\n"
        with open(os.path.join(td, "data", "data.json"), "w") as f:
            f.write(payload)
        with tarfile.open(backup, "w:gz") as tf:
            tf.add(os.path.join(td, "data", "data.json"), arcname="data/data.json")
    os.chmod(backup, 0o644)

    result = subprocess.run(
        ["runuser", "-u", "user", "--", "bash", DEPLOY],
        capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, f"deploy.sh failed: {result.stderr}"

    wait_until(lambda: listener_owners(8080) and listener_owners(9090), 8,
               "Expected listeners on both 8080 and 9090")
    status, data = get_url("/api/data")
    assert status == 200
    assert '{"status": "recovered"}' in data, "API did not return expected restored data."
    assert nonce in data, "deploy.sh did not restore the verifier-provided backup data."
    assert open(os.path.join(PROJECT_DIR, "data", "data.json")).read() == data

    assert os.path.isfile(SUPERVISOR), "supervisor.sh does not exist."
    assert os.access(SUPERVISOR, os.X_OK), "supervisor.sh is not executable."
    assert os.path.isfile(MONITOR), "health_monitor.sh does not exist."
    assert os.access(MONITOR, os.X_OK), "health_monitor.sh is not executable."

    servers = server_pids()
    assert len(servers) == 1, f"Expected exactly one python3 server.py process, found {servers}"
    server_pid = servers[0]
    assert uid_of(server_pid) == USER_UID, "server.py was not launched as the unprivileged user."
    assert server_pid in listener_owners(8080), "server.py does not own the port 8080 listener."

    parent = ppid(server_pid)
    assert parent in script_pids(SUPERVISOR), "server.py is not a child of supervisor.sh."
    assert uid_of(parent) == USER_UID

    owners9090 = listener_owners(9090)
    socat_owners = []
    for pid in owners9090:
        args = cmdline(pid)
        text = " ".join(args).lower()
        if args and os.path.basename(args[0]) == "socat":
            assert "9090" in text and "8080" in text and "127.0.0.1" in text, \
                f"socat has incorrect forwarding arguments: {args}"
            socat_owners.append(pid)
    assert socat_owners, "The port 9090 listener is not owned by socat."
    assert all(uid_of(pid) == USER_UID for pid in socat_owners)


def test_supervisor_restart_and_logging():
    before = valid_start_entries()
    assert before, "No timestamped initial startup entry was written to server.log."
    assert all(match is not None for _, match in before), \
        "Starting server entries must exactly match [YYYY-MM-DD HH:MM:SS] Starting server."

    old_pid = server_pids()[0]
    crash_time = time.time()
    try:
        urllib.request.urlopen("http://127.0.0.1:9090/crash", timeout=2)
    except Exception:
        pass

    def restarted():
        pids = server_pids()
        return pids[0] if len(pids) == 1 and pids[0] != old_pid and pids[0] in listener_owners(8080) else 0

    new_pid = wait_until(restarted, 10, "server.py was not restarted by the supervisor")
    status, body = get_url("/health")
    assert status == 200 and body == "healthy", "Server did not return 'healthy' after restart."
    assert ppid(new_pid) in script_pids(SUPERVISOR), "Restarted server is not supervised by supervisor.sh."

    after = valid_start_entries()
    assert len(after) >= len(before) + 1, "No new startup log entry was produced by the actual restart."
    assert all(match is not None for _, match in after), \
        "Starting server entries must exactly match [YYYY-MM-DD HH:MM:SS] Starting server."
    newest = datetime.datetime.strptime(after[-1][1].group(1), "%Y-%m-%d %H:%M:%S").timestamp()
    assert crash_time - 2 <= newest <= time.time() + 2, "Restart log timestamp does not match the restart event."


def test_health_monitor_logging_and_cadence():
    monitors = script_pids(MONITOR)
    assert monitors, "health_monitor.sh is not running."
    assert all(uid_of(pid) == USER_UID for pid in monitors)
    monitor_pid = monitors[0]

    server_pid = server_pids()[0]
    os.kill(server_pid, signal.SIGSTOP)
    saw_curl = False
    try:
        deadline = time.time() + 3
        while time.time() < deadline and not saw_curl:
            for pid in all_pids():
                args = cmdline(pid)
                if (args and os.path.basename(args[0]) == "curl"
                        and "http://127.0.0.1:9090/health" in args
                        and is_descendant(pid, monitor_pid)):
                    saw_curl = True
                    break
            time.sleep(0.01)
    finally:
        os.kill(server_pid, signal.SIGCONT)
    assert saw_curl, "health_monitor.sh was not observed running curl against the required health URL."

    os.makedirs(LOGS, exist_ok=True)
    with open(HEALTH_LOG, "w"):
        pass
    events = []
    previous = 0
    deadline = time.monotonic() + 5.2
    while time.monotonic() < deadline:
        try:
            lines = open(HEALTH_LOG).read().splitlines()
        except FileNotFoundError:
            lines = []
        if len(lines) > previous:
            now = time.monotonic()
            for _ in range(len(lines) - previous):
                events.append(now)
            previous = len(lines)
        time.sleep(0.04)

    lines = open(HEALTH_LOG).read().splitlines()
    assert lines, "health.log does not exist or is empty."
    assert all(line in ("OK", "FAILED") for line in lines), "health.log contains invalid status lines."
    assert "OK" in lines, "Health monitor is not logging 'OK' to health.log."
    assert len(events) >= 4, f"Health monitor logged only {len(events)} checks in five seconds."
    intervals = [b - a for a, b in zip(events, events[1:])]
    assert all(0.65 <= value <= 1.45 for value in intervals[-3:]), \
        f"Health checks are not occurring every second: intervals={intervals}"


def test_logrotate_configuration():
    conf = os.path.join(PROJECT_DIR, "logrotate.conf")
    status_file = os.path.join(PROJECT_DIR, "logrotate.status")
    assert os.path.isfile(conf), "logrotate.conf does not exist."
    text = open(conf).read()
    uncommented = "\n".join(line.split("#", 1)[0] for line in text.splitlines())
    assert re.search(r"/home/user/infra_project/logs/(?:\*\.log|[^\s{]*\.log)", uncommented), \
        "logrotate.conf does not manage logs/*.log."
    assert re.search(r"(?m)^\s*daily\s*$", uncommented)
    assert re.search(r"(?m)^\s*rotate\s+3\s*$", uncommented)
    assert re.search(r"(?m)^\s*compress\s*$", uncommented)
    assert re.search(r"(?m)^\s*missingok\s*$", uncommented)
    assert not re.search(r"(?mi)^\s*su\s+root(?:\s|$)", uncommented), \
        "logrotate.conf requests root permissions."

    try:
        os.remove(status_file)
    except FileNotFoundError:
        pass
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "logrotate", "-s", status_file, "-f", conf],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"logrotate failed: {result.stderr}"
    assert os.path.isfile(status_file), "The required local logrotate state file was not created."

    rotated = [name for name in os.listdir(LOGS)
               if "server.log.1" in name or "health.log.1" in name]
    assert rotated, "No rotated log files found after forcing logrotate."
    compressed = [name for name in rotated if name.endswith(".gz")]
    assert compressed, "Rotated log files are not compressed (.gz expected)."
    for name in compressed:
        with gzip.open(os.path.join(LOGS, name), "rb") as f:
            f.read()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
