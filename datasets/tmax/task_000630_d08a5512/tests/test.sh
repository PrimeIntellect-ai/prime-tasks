#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import pwd
import secrets
import shutil
import signal
import subprocess
import sys
import tarfile
import time
import pytest

SUPERVISOR = "/home/user/supervise.py"
PID_FILE = "/home/user/app.pid"
WORKER = "/home/user/worker.py"
ARCHIVE = "/home/user/backup/data_archive.tar.gz"
ALERTS = "/home/user/alerts.log"
LAUNCH_STATE = "/home/user/launch_state.txt"
ALERT = "ALERT: Worker down. Backup created."


def test_backup_archive_exists_and_valid():
    archive_path = "/home/user/backup/data_archive.tar.gz"
    assert os.path.isfile(archive_path), f"Backup archive {archive_path} does not exist."

    try:
        with tarfile.open(archive_path, "r:gz") as tar:
            names = tar.getnames()
            basenames = [os.path.basename(n) for n in names]
            assert "metric1.csv" in basenames, "metric1.csv not found in the backup archive."
            assert "metric2.csv" in basenames, "metric2.csv not found in the backup archive."
    except tarfile.TarError as e:
        pytest.fail(f"Backup archive is not a valid tar.gz file: {e}")


def test_alerts_log_content():
    log_path = "/home/user/alerts.log"
    assert os.path.isfile(log_path), f"Alerts log {log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read()
    expected_alert = "ALERT: Worker down. Backup created."
    assert expected_alert in content, f"Expected alert message '{expected_alert}' not found in {log_path}."


def test_worker_running_and_pid_updated():
    pid_file = "/home/user/app.pid"
    assert os.path.isfile(pid_file), f"PID file {pid_file} does not exist."

    with open(pid_file, "r") as f:
        pid_str = f.read().strip()

    assert pid_str.isdigit(), f"PID file does not contain a valid numeric PID: '{pid_str}'"
    pid = int(pid_str)

    proc_dir = f"/proc/{pid}"
    assert os.path.isdir(proc_dir), f"Process with PID {pid} is not running."

    cmdline_file = os.path.join(proc_dir, "cmdline")
    assert os.path.isfile(cmdline_file), f"Cannot read cmdline for PID {pid}."

    with open(cmdline_file, "r") as f:
        cmdline = f.read().replace('\x00', ' ')

    assert "worker.py" in cmdline, f"Process {pid} is running, but does not appear to be worker.py. Cmdline: {cmdline}"


def read_pid():
    with open(PID_FILE) as f:
        value = f.read().strip()
    assert value.isdigit(), f"PID file is not numeric: {value!r}"
    return int(value)


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def stop_worker_from_pid_file():
    try:
        pid = read_pid()
    except (OSError, AssertionError):
        return
    if "worker.py" not in cmdline(pid):
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    for _ in range(50):
        if not os.path.exists(f"/proc/{pid}") or not cmdline(pid):
            return
        time.sleep(0.05)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def run_supervisor():
    result = subprocess.run(
        ["runuser", "-u", "user", "--", sys.executable, SUPERVISOR],
        timeout=6,
    )
    assert result.returncode == 0, f"Supervisor exited with status {result.returncode}"


def assert_archive(expected):
    assert os.path.isfile(ARCHIVE), "Recovery did not create the archive"
    try:
        with tarfile.open(ARCHIVE, "r:gz") as tar:
            members = {m.name: m for m in tar.getmembers() if m.isfile()}
            for relative_name, expected_bytes in expected.items():
                matches = [m for name, m in members.items() if name == relative_name or name.endswith("/" + relative_name)]
                assert len(matches) == 1, f"Archive does not contain exactly one {relative_name!r}"
                extracted = tar.extractfile(matches[0])
                assert extracted is not None
                assert extracted.read() == expected_bytes, f"Wrong archived content for {relative_name!r}"
    except tarfile.TarError as exc:
        pytest.fail(f"Recovery archive is invalid: {exc}")


def assert_subprocess_popen_used(tree):
    module_aliases = set()
    popen_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "subprocess":
                    module_aliases.add(alias.asname or "subprocess")
        elif isinstance(node, ast.ImportFrom) and node.module == "subprocess":
            for alias in node.names:
                if alias.name == "Popen":
                    popen_aliases.add(alias.asname or "Popen")

    found = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in popen_aliases:
            found = True
        if (isinstance(node.func, ast.Attribute) and node.func.attr == "Popen"
                and isinstance(node.func.value, ast.Name)
                and node.func.value.id in module_aliases):
            found = True
    assert found, "supervise.py must launch the worker asynchronously with subprocess.Popen"


def test_supervisor_behavior_on_healthy_stale_invalid_and_missing_pid():
    assert os.path.isfile(SUPERVISOR), f"Required script {SUPERVISOR} does not exist"
    assert not os.path.islink(SUPERVISOR), "supervise.py must be a regular Python file"
    with open(SUPERVISOR, "rb") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SUPERVISOR)
    except SyntaxError as exc:
        pytest.fail(f"supervise.py is not valid Python: {exc}")
    assert_subprocess_popen_used(tree)

    original_worker = open(WORKER, "rb").read()
    original_mode = os.stat(WORKER).st_mode
    user = pwd.getpwnam("user")
    running_pid = read_pid()
    assert "worker.py" in cmdline(running_pid), "Initial worker is not running"

    token = secrets.token_hex(12)
    top_name = f"sample_{token}.csv"
    nested_name = f"nested_{token}/detail_{token}.txt"
    expected = {
        top_name: ("top:" + token).encode(),
        nested_name: ("nested:" + token).encode(),
    }

    probe = '''#!/usr/bin/env python3
import os
import time
archive = "/home/user/backup/data_archive.tar.gz"
alerts = "/home/user/alerts.log"
ready = os.path.isfile(archive)
try:
    with open(alerts) as f:
        ready = ready and f.read().splitlines()[-1] == "ALERT: Worker down. Backup created."
except Exception:
    ready = False
with open("/home/user/launch_state.txt", "w") as f:
    f.write("ready" if ready else "launched-before-backup-or-alert")
with open("/home/user/app.pid", "w") as f:
    f.write(str(os.getpid()))
time.sleep(10000)
'''

    try:
        # A healthy worker must cause no backup, alert, restart, or PID rewrite.
        for path in (ARCHIVE, ALERTS, LAUNCH_STATE):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        before_pid_bytes = open(PID_FILE, "rb").read()
        run_supervisor()
        assert open(PID_FILE, "rb").read() == before_pid_bytes, "Healthy-state run rewrote the PID file"
        assert os.path.exists(f"/proc/{running_pid}"), "Healthy-state run disrupted the worker"
        assert not os.path.exists(ARCHIVE), "Healthy-state run created a backup"
        assert not os.path.exists(ALERTS), "Healthy-state run wrote an alert"
        assert not os.path.exists(LAUNCH_STATE), "Healthy-state run launched another worker"

        stop_worker_from_pid_file()
        shutil.rmtree("/home/user/data")
        os.makedirs(os.path.dirname("/home/user/data/" + nested_name), exist_ok=True)
        for relative_name, data in expected.items():
            path = os.path.join("/home/user/data", relative_name)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(data)
        os.chown("/home/user/data", user.pw_uid, user.pw_gid)
        for root, dirs, files in os.walk("/home/user/data"):
            os.chown(root, user.pw_uid, user.pw_gid)
            for name in dirs + files:
                os.chown(os.path.join(root, name), user.pw_uid, user.pw_gid)

        with open(WORKER, "w") as f:
            f.write(probe)
        os.chmod(WORKER, 0o755)
        os.chown(WORKER, user.pw_uid, user.pw_gid)

        # Exercise all specified unhealthy PID states, including a numeric stale PID.
        cases = (("stale", "999999\n"), ("invalid", "not-a-pid\n"), ("missing", None))
        for index, (case, pid_contents) in enumerate(cases, 1):
            for path in (ARCHIVE, LAUNCH_STATE):
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass
            if pid_contents is None:
                try:
                    os.remove(PID_FILE)
                except FileNotFoundError:
                    pass
            else:
                with open(PID_FILE, "w") as f:
                    f.write(pid_contents)
                os.chown(PID_FILE, user.pw_uid, user.pw_gid)

            run_supervisor()
            time.sleep(0.3)
            assert_archive(expected)
            assert os.path.isfile(LAUNCH_STATE), f"Worker was not launched for {case} PID"
            assert open(LAUNCH_STATE).read() == "ready", "Worker launched before backup and alert were available"
            with open(ALERTS, "rb") as f:
                alert_bytes = f.read()
            assert alert_bytes == ((ALERT + "\n") * index).encode(), "Alert was not appended as an exact new line"
            new_pid = read_pid()
            assert new_pid != running_pid
            assert "worker.py" in cmdline(new_pid), f"Restarted worker is not alive after supervisor exit ({case} PID)"
            stop_worker_from_pid_file()
    finally:
        stop_worker_from_pid_file()
        with open(WORKER, "wb") as f:
            f.write(original_worker)
        os.chmod(WORKER, original_mode)
        os.chown(WORKER, user.pw_uid, user.pw_gid)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
