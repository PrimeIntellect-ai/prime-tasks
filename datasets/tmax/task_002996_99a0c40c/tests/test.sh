#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import socket
import stat
import subprocess
import threading
import time
import uuid

SUPERVISOR_PATH = "/home/user/supervisor.sh"
EXPORTER_PATH = "/home/user/exporter.py"
SUPERVISOR_LOG = "/home/user/supervisor.log"
METRICS_LOG = "/home/user/metrics.log"
CONFIG_PATH = "/home/user/observability/config.ini"
FSTAB_PATH = "/home/user/observability/fstab.mock"
TEST_MNT = "/home/user/test_mnt"
RUNUSER = "/usr/sbin/runuser"

BASE_CONFIG = """[backend]
target_port = 8888

[storage]
mount_device = /dev/mapper/data-vol
"""
BASE_FSTAB = """/dev/mapper/os-vol / ext4 defaults 1 1
/dev/mapper/data-vol /home/user/test_mnt ext4 defaults,noatime 0 2
"""

USER_INFO = pwd.getpwnam("user")


def write_observability_files(config=BASE_CONFIG, fstab=BASE_FSTAB):
    with open(CONFIG_PATH, "w") as f:
        f.write(config)
    with open(FSTAB_PATH, "w") as f:
        f.write(fstab)
    os.chown(CONFIG_PATH, USER_INFO.pw_uid, USER_INFO.pw_gid)
    os.chown(FSTAB_PATH, USER_INFO.pw_uid, USER_INFO.pw_gid)


def remove_file(path):
    if os.path.exists(path):
        os.remove(path)


def run_supervisor(timeout=20):
    return subprocess.run(
        [RUNUSER, "-u", "user", "--", SUPERVISOR_PATH],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def setup_module(module):
    write_observability_files()
    for path in [SUPERVISOR_LOG, METRICS_LOG]:
        remove_file(path)
    if os.path.isdir(TEST_MNT):
        os.rmdir(TEST_MNT)


def teardown_module(module):
    write_observability_files()
    for path in [SUPERVISOR_LOG, METRICS_LOG]:
        remove_file(path)
    if os.path.isdir(TEST_MNT):
        os.rmdir(TEST_MNT)


def test_supervisor_executable():
    assert os.path.isfile(SUPERVISOR_PATH), f"Supervisor script missing at {SUPERVISOR_PATH}"
    st = os.stat(SUPERVISOR_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Supervisor script {SUPERVISOR_PATH} is not executable."
    assert os.path.isfile(EXPORTER_PATH), f"Exporter script missing at {EXPORTER_PATH}"
    assert not os.path.islink(EXPORTER_PATH), "Exporter must be a regular Python script, not a symlink"


def test_exporter_rejects_wrong_uid():
    result = subprocess.run(
        ["python3", EXPORTER_PATH], capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 4, (
        f"Expected exporter run as root to exit immediately with 4, got {result.returncode}"
    )


def test_connectivity_failure():
    remove_file(SUPERVISOR_LOG)
    result = run_supervisor()

    assert result.returncode == 1, f"Expected supervisor to exit with 1 on connectivity failure, got {result.returncode}"
    assert os.path.isfile(SUPERVISOR_LOG), f"{SUPERVISOR_LOG} was not created."
    with open(SUPERVISOR_LOG, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_line = "Restarting exporter, previous exit code: 2"
    count = lines.count(expected_line)
    assert count == 3, f"Expected 3 occurrences of '{expected_line}' in {SUPERVISOR_LOG}, found {count}. Lines: {lines}"


def listener_thread(port, stop_event):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(("127.0.0.1", port))
        s.listen(5)
        s.settimeout(0.5)
        while not stop_event.is_set():
            try:
                conn, _ = s.accept()
                conn.close()
            except socket.timeout:
                continue
            except Exception:
                break


def test_mount_failure():
    remove_file(SUPERVISOR_LOG)
    if os.path.isdir(TEST_MNT):
        os.rmdir(TEST_MNT)

    stop_event = threading.Event()
    thread = threading.Thread(target=listener_thread, args=(8888, stop_event))
    thread.start()
    try:
        time.sleep(0.2)
        result = run_supervisor()
        assert result.returncode == 1, f"Expected supervisor to exit with 1 on mount failure, got {result.returncode}"
        assert os.path.isfile(SUPERVISOR_LOG), f"{SUPERVISOR_LOG} was not created."
        with open(SUPERVISOR_LOG, "r") as f:
            lines = [line.strip() for line in f.readlines() if line.strip()]

        expected_line = "Restarting exporter, previous exit code: 3"
        count = lines.count(expected_line)
        assert count == 3, f"Expected 3 occurrences of '{expected_line}' in {SUPERVISOR_LOG}, found {count}. Lines: {lines}"
    finally:
        stop_event.set()
        thread.join()


def test_success():
    remove_file(SUPERVISOR_LOG)
    remove_file(METRICS_LOG)
    os.makedirs(TEST_MNT, exist_ok=True)

    stop_event = threading.Event()
    thread = threading.Thread(target=listener_thread, args=(8888, stop_event))
    thread.start()
    try:
        time.sleep(0.2)
        result = run_supervisor()
        assert result.returncode == 0, f"Expected supervisor to exit with 0 on success, got {result.returncode}"
        assert os.path.isfile(METRICS_LOG), f"{METRICS_LOG} was not created."
        with open(METRICS_LOG, "r") as f:
            lines = [line.strip() for line in f.readlines() if line.strip()]

        assert len(lines) >= 1, f"Expected at least one line in {METRICS_LOG}"
        last_line = lines[-1]
        try:
            data = json.loads(last_line)
        except json.JSONDecodeError:
            assert False, f"Failed to parse JSON from {METRICS_LOG}: {last_line}"

        assert data.get("status") == "ok", f"Expected status 'ok', got {data.get('status')}"
        assert data.get("port") == 8888, f"Expected port 8888, got {data.get('port')}"
        assert data.get("mount_dir") == TEST_MNT, f"Expected mount_dir '{TEST_MNT}', got {data.get('mount_dir')}"
    finally:
        stop_event.set()
        thread.join()


def test_dynamic_config_and_fstab():
    token = uuid.uuid4().hex
    device = f"/dev/mapper/dynamic-{token}"
    mount_path = f"/home/user/dynamic_mnt_{token}"
    remove_file(SUPERVISOR_LOG)
    remove_file(METRICS_LOG)
    os.makedirs(mount_path)

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    port = listener.getsockname()[1]
    listener.listen(5)
    listener.settimeout(0.5)
    stop_event = threading.Event()

    def accept_connections():
        while not stop_event.is_set():
            try:
                conn, _ = listener.accept()
                conn.close()
            except socket.timeout:
                continue
            except OSError:
                break

    thread = threading.Thread(target=accept_connections)
    thread.start()
    dynamic_config = f"[backend]\ntarget_port = {port}\n\n[storage]\nmount_device = {device}\n"
    dynamic_fstab = BASE_FSTAB + f"{device} {mount_path} ext4 defaults 0 2\n"

    try:
        write_observability_files(dynamic_config, dynamic_fstab)
        result = run_supervisor()
        assert result.returncode == 0, f"Expected dynamic configuration to succeed, got {result.returncode}"
        assert os.path.isfile(METRICS_LOG), f"{METRICS_LOG} was not created."
        with open(METRICS_LOG, "r") as f:
            lines = [line.strip() for line in f if line.strip()]
        expected = f'{{"status": "ok", "port": {port}, "mount_dir": "{mount_path}"}}'
        assert lines == [expected], f"Expected exactly {expected!r}, got {lines!r}"
    finally:
        stop_event.set()
        listener.close()
        thread.join()
        write_observability_files()
        if os.path.isdir(mount_path):
            os.rmdir(mount_path)


def test_supervisor_actually_executes_exporter_and_retries_it():
    marker = f"/tmp/exporter_marker_{uuid.uuid4().hex}"
    remove_file(SUPERVISOR_LOG)
    original_stat = os.stat(EXPORTER_PATH)
    with open(EXPORTER_PATH, "rb") as f:
        original = f.read()

    stub = (
        "with open(" + repr(marker) + ", 'a') as f:\n"
        "    f.write('attempt\\n')\n"
        "raise SystemExit(7)\n"
    ).encode()

    try:
        with open(EXPORTER_PATH, "wb") as f:
            f.write(stub)
        os.chown(EXPORTER_PATH, USER_INFO.pw_uid, USER_INFO.pw_gid)
        result = run_supervisor()
        assert result.returncode == 1, f"Expected supervisor to fail after retries, got {result.returncode}"
        assert os.path.isfile(marker), "Supervisor did not execute /home/user/exporter.py"
        with open(marker, "r") as f:
            attempts = [line.strip() for line in f if line.strip()]
        assert attempts == ["attempt"] * 4, f"Expected 4 exporter executions, got {len(attempts)}"
        with open(SUPERVISOR_LOG, "r") as f:
            lines = [line.strip() for line in f if line.strip()]
        expected_line = "Restarting exporter, previous exit code: 7"
        assert lines.count(expected_line) == 3, f"Expected 3 restart messages for code 7, got {lines}"
    finally:
        with open(EXPORTER_PATH, "wb") as f:
            f.write(original)
        os.chmod(EXPORTER_PATH, stat.S_IMODE(original_stat.st_mode))
        os.chown(EXPORTER_PATH, original_stat.st_uid, original_stat.st_gid)
        remove_file(marker)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
