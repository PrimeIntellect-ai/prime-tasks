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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import errno
import json
import os
import pwd
import random
import socket
import stat
import subprocess
import tarfile
import threading
import time
import uuid

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
PLANNER = "/home/user/planner.py"
PROFILER = "/app/bin/sys-profiler"
USER_UID = pwd.getpwnam("user").pw_uid
USER_GID = pwd.getpwnam("user").pw_gid


def wait_until(predicate, timeout=10, interval=0.1):
    end = time.time() + timeout
    last_error = None
    while time.time() < end:
        try:
            value = predicate()
            if value:
                return value
        except Exception as exc:
            last_error = exc
        time.sleep(interval)
    if last_error:
        raise AssertionError(f"condition did not become true: {last_error}")
    raise AssertionError("condition did not become true before timeout")


def listener_inode(port):
    wanted_port = f"{port:04X}"
    for table in ("/proc/net/tcp",):
        with open(table) as fp:
            next(fp)
            for line in fp:
                fields = line.split()
                local_address = fields[1]
                state = fields[3]
                ip_hex, port_hex = local_address.split(":")
                if ip_hex == "0100007F" and port_hex == wanted_port and state == "0A":
                    return fields[9]
    return None


def pid_for_listener(port):
    inode = listener_inode(port)
    if not inode:
        return None
    needle = f"socket:[{inode}]"
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) == needle:
                        return int(entry)
                except OSError:
                    pass
        except OSError:
            pass
    return None


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as fp:
            return [part.decode(errors="replace") for part in fp.read().split(b"\0") if part]
    except OSError:
        return []


def proc_uid(pid):
    return os.stat(f"/proc/{pid}").st_uid


def is_descendant(pid, ancestor):
    seen = set()
    while pid > 1 and pid not in seen:
        if pid == ancestor:
            return True
        seen.add(pid)
        try:
            with open(f"/proc/{pid}/stat") as fp:
                pid = int(fp.read().split()[3])
        except (OSError, ValueError, IndexError):
            return False
    return False


def profiler_args(pid):
    args = cmdline(pid)
    port = None
    data_dir = None
    for index, arg in enumerate(args):
        if arg == "--tcp-port" and index + 1 < len(args):
            port = int(args[index + 1])
        elif arg.startswith("--tcp-port="):
            port = int(arg.split("=", 1)[1])
        elif arg == "--data-dir" and index + 1 < len(args):
            data_dir = args[index + 1]
        elif arg.startswith("--data-dir="):
            data_dir = arg.split("=", 1)[1]
    return port, data_dir


def genuine_profiler_listener(planner_pid=None):
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        try:
            exe = os.path.realpath(f"/proc/{pid}/exe")
            if exe != PROFILER or proc_uid(pid) != USER_UID:
                continue
            port, data_dir = profiler_args(pid)
            if port is None or data_dir != "/home/user/metrics/current":
                continue
            if pid_for_listener(port) != pid:
                continue
            if planner_pid is not None and not is_descendant(pid, planner_pid):
                continue
            return pid, port
        except (OSError, ValueError):
            pass
    return None


def get_plan():
    response = requests.get(f"{BASE_URL}/plan", timeout=5)
    assert response.status_code == 200, f"Expected 200 for GET /plan, got {response.status_code}"
    return response.json()


def test_artifact_and_running_identity():
    assert os.path.isfile(PLANNER), f"Missing required artifact {PLANNER}"
    assert not os.path.islink(PLANNER), f"{PLANNER} must be a regular Python file"
    subprocess.run(["python3", "-m", "py_compile", PLANNER], check=True)

    planner_pid = pid_for_listener(8080)
    assert planner_pid is not None, "Nothing is listening on 127.0.0.1:8080"
    assert proc_uid(planner_pid) == USER_UID, "planner is running with root or another user's privileges"
    assert any(os.path.realpath(arg) == PLANNER for arg in cmdline(planner_pid)), \
        "The process serving port 8080 is not /home/user/planner.py"

    profiler = genuine_profiler_listener(planner_pid)
    assert profiler is not None, "A genuine /app/bin/sys-profiler child with the required flags is not listening"


def test_api_gateway_metrics_and_plan():
    # Preserve the original fixed checks.
    resp1 = requests.post(f"{BASE_URL}/metric", json={"cpu": 10, "mem": 512}, timeout=5)
    assert resp1.status_code in (200, 201), f"Expected 200 or 201 for POST /metric, got {resp1.status_code}"

    resp2 = requests.post(f"{BASE_URL}/metric", json={"cpu": 5, "mem": 256}, timeout=5)
    assert resp2.status_code in (200, 201), f"Expected 200 or 201 for POST /metric, got {resp2.status_code}"

    resp3 = requests.get(f"{BASE_URL}/plan", timeout=5)
    assert resp3.status_code == 200, f"Expected 200 for GET /plan, got {resp3.status_code}"
    data = resp3.json()
    assert data.get("status") == "ok", f"Expected status 'ok', got {data.get('status')}"
    assert "total_cpu" in data, "Missing 'total_cpu' in response"
    assert "total_mem" in data, "Missing 'total_mem' in response"
    assert data["total_cpu"] >= 15, f"Expected total_cpu >= 15, got {data['total_cpu']}"
    assert data["total_mem"] >= 768, f"Expected total_mem >= 768, got {data['total_mem']}"

    # Use unpredictable values and compare exact deltas against a baseline.
    baseline = get_plan()
    assert isinstance(baseline.get("total_cpu"), (int, float))
    assert isinstance(baseline.get("total_mem"), (int, float))

    cpu_values = [random.randint(1001, 9000), random.randint(10001, 50000), random.randint(50001, 90000)]
    mem_values = [random.randint(90001, 150000), random.randint(150001, 250000), random.randint(250001, 350000)]
    token = uuid.uuid4().hex
    for cpu, mem in zip(cpu_values, mem_values):
        response = requests.post(
            f"{BASE_URL}/metric",
            json={"cpu": cpu, "mem": mem, "verification_token": token},
            timeout=5,
        )
        assert response.status_code in (200, 201)

    updated = get_plan()
    assert updated.get("status") == "ok"
    assert updated["total_cpu"] == baseline["total_cpu"] + sum(cpu_values)
    assert updated["total_mem"] == baseline["total_mem"] + sum(mem_values)

    target = os.path.realpath("/home/user/metrics/current")
    matching_files = []
    for name in os.listdir(target):
        path = os.path.join(target, name)
        if not os.path.isfile(path):
            continue
        try:
            with open(path) as fp:
                payload = json.load(fp)
            if payload.get("verification_token") == token:
                matching_files.append(payload)
        except Exception:
            pass
    assert len(matching_files) == 3, "Each POST /metric must create a new JSON file in current"


def test_process_supervision_and_gateway_profiler_protocol():
    planner_pid = pid_for_listener(8080)
    assert planner_pid is not None
    found = genuine_profiler_listener(planner_pid)
    assert found is not None, "sys-profiler process is not running"
    pid1, port = found

    # Kill the exact profiler listener, immediately occupy its configured port,
    # and return an unpredictable response. This proves /plan contacts that port,
    # sends the reverse-engineered trigger, and relays the profiler response.
    os.kill(pid1, 9)
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    bound = False
    deadline = time.time() + 3
    while time.time() < deadline and not bound:
        try:
            probe.bind(("127.0.0.1", port))
            bound = True
        except OSError as exc:
            if exc.errno != errno.EADDRINUSE:
                raise
            replacement = pid_for_listener(port)
            if replacement and replacement != os.getpid():
                try:
                    if os.path.realpath(f"/proc/{replacement}/exe") == PROFILER:
                        os.kill(replacement, 9)
                except OSError:
                    pass
            time.sleep(0.02)
    assert bound, "Could not take over the configured profiler port after killing it"
    probe.listen(1)
    probe.settimeout(5)

    nonce = random.randint(10**8, 10**9 - 1)
    expected = {"status": "ok", "total_cpu": nonce, "total_mem": nonce + 7, "probe": uuid.uuid4().hex}
    captured = []
    errors = []

    def serve_probe():
        try:
            conn, _ = probe.accept()
            with conn:
                conn.settimeout(3)
                captured.append(conn.recv(1024))
                conn.sendall((json.dumps(expected) + "\n").encode())
        except Exception as exc:
            errors.append(exc)

    thread = threading.Thread(target=serve_probe)
    thread.start()
    response = requests.get(f"{BASE_URL}/plan", timeout=5)
    thread.join(5)
    probe.close()

    assert not errors, f"Gateway did not contact the configured profiler port: {errors}"
    assert captured == [b"GENERATE_PLAN\n"], f"Wrong profiler trigger payload: {captured!r}"
    assert response.status_code == 200
    assert response.json() == expected, "GET /plan did not return the profiler TCP response directly"

    # Preserve and strengthen the original crash/restart assertions.
    pid2, _ = wait_until(lambda: genuine_profiler_listener(planner_pid), timeout=10)
    assert pid2 is not None, "sys-profiler process was not restarted after being killed"
    assert pid1 != pid2, "sys-profiler process PID did not change after restart"


def test_backup_on_new_run_and_relaunch_without_root():
    metrics_dir = "/home/user/metrics"
    old_target = os.path.realpath(os.path.join(metrics_dir, "current"))
    assert os.path.isdir(old_target)

    marker_name = f"backup_probe_{uuid.uuid4().hex}.txt"
    marker_path = os.path.join(old_target, marker_name)
    with open(marker_path, "w") as fp:
        fp.write(uuid.uuid4().hex)
    os.chown(marker_path, USER_UID, USER_GID)
    os.chmod(marker_path, 0o700)

    planner_pid = pid_for_listener(8080)
    assert planner_pid is not None
    descendants = [int(p) for p in os.listdir("/proc") if p.isdigit() and is_descendant(int(p), planner_pid)]
    os.kill(planner_pid, 9)
    for pid in descendants:
        if pid != planner_pid:
            try:
                os.kill(pid, 9)
            except ProcessLookupError:
                pass

    wait_until(lambda: pid_for_listener(8080) is None, timeout=5)
    # Avoid a same-second run directory collision in timestamp-based implementations.
    time.sleep(1.2)

    log = open("/tmp/planner-verifier-relaunch.log", "ab", buffering=0)
    subprocess.Popen(
        ["runuser", "-u", "user", "--", "python3", PLANNER],
        stdin=subprocess.DEVNULL,
        stdout=log,
        stderr=log,
        start_new_session=True,
    )

    def ready():
        pid = pid_for_listener(8080)
        if not pid or proc_uid(pid) != USER_UID:
            return None
        try:
            response = requests.get(f"{BASE_URL}/plan", timeout=1)
            if response.status_code == 200:
                return pid
        except Exception:
            pass
        return None

    new_planner_pid = wait_until(ready, timeout=15)
    assert new_planner_pid != planner_pid
    new_target = os.path.realpath(os.path.join(metrics_dir, "current"))
    assert new_target != old_target, "A new timestamped run directory was not created on restart"
    assert not os.path.exists(old_target), "The older run directory was not deleted after archiving"

    backups = "/home/user/backups"
    assert os.path.isdir(backups), "Backup directory was not created"

    def archive_with_marker():
        for name in os.listdir(backups):
            if not name.endswith(".tar.gz"):
                continue
            path = os.path.join(backups, name)
            try:
                with tarfile.open(path, "r:gz") as archive:
                    if any(os.path.basename(member.name) == marker_name for member in archive.getmembers()):
                        return path
            except (OSError, tarfile.TarError):
                pass
        return None

    assert wait_until(archive_with_marker, timeout=8), "No .tar.gz backup contains the prior run's marker"


def test_filesystem_state():
    metrics_dir = "/home/user/metrics"
    current_link = os.path.join(metrics_dir, "current")

    assert os.path.exists(metrics_dir), "Metrics directory does not exist"
    assert os.path.islink(current_link), "'current' is not a symlink"

    target_dir = os.path.realpath(current_link)
    assert os.path.isdir(target_dir), "Symlink 'current' does not point to a valid directory"

    st = os.stat(metrics_dir)
    assert stat.S_IMODE(st.st_mode) == 0o700, f"Expected permissions 0700 for {metrics_dir}, got {oct(stat.S_IMODE(st.st_mode))}"

    st = os.stat(target_dir)
    assert stat.S_IMODE(st.st_mode) == 0o700, f"Expected permissions 0700 for {target_dir}, got {oct(stat.S_IMODE(st.st_mode))}"

    for root, dirs, files in os.walk(target_dir):
        for directory in dirs:
            st = os.stat(os.path.join(root, directory))
            assert stat.S_IMODE(st.st_mode) == 0o700, f"Expected permissions 0700 for directory {directory}"
        for filename in files:
            st = os.stat(os.path.join(root, filename))
            assert stat.S_IMODE(st.st_mode) == 0o700, f"Expected permissions 0700 for file {filename}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
