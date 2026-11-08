#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import stat
import subprocess
import tempfile
import time

APP_DATA_DIR = "/home/user/app_data"
TRIGGER_SCRIPT = "/home/user/trigger_worker.sh"
MONITOR_SCRIPT = "/home/user/monitor.sh"
ALERT_LOG = "/home/user/alert.log"
HOME_DATA_LOG = "/home/user/data.log"
APP_DATA_LOG = "/home/user/app_data/data.log"
WORKER = "/home/user/bin/service_worker"


def kill_workers():
    subprocess.run(["pkill", "-f", WORKER], check=False)
    deadline = time.time() + 3
    while time.time() < deadline:
        result = subprocess.run(["pgrep", "-f", WORKER], capture_output=True)
        if result.returncode != 0:
            return
        time.sleep(0.1)


def clean_app_data():
    kill_workers()
    os.makedirs(APP_DATA_DIR, exist_ok=True)
    for name in os.listdir(APP_DATA_DIR):
        path = os.path.join(APP_DATA_DIR, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
    if os.path.exists(ALERT_LOG):
        os.unlink(ALERT_LOG)


def run_monitor():
    subprocess.run(["bash", MONITOR_SCRIPT], check=True, timeout=10)
    assert os.path.isfile(ALERT_LOG), f"{ALERT_LOG} was not created."
    with open(ALERT_LOG, "r") as f:
        return f.read().strip()


def directory_bytes():
    output = subprocess.check_output(["du", "-sb", APP_DATA_DIR], text=True)
    return int(output.split()[0])


def wait_for_no_workers():
    deadline = time.time() + 4
    while time.time() < deadline:
        result = subprocess.run(["pgrep", "-f", WORKER], capture_output=True)
        if result.returncode != 0:
            return
        time.sleep(0.1)
    assert False, "service_worker process was not killed by monitor.sh."


def start_stable_worker():
    target = tempfile.mkdtemp(prefix="worker-target-")
    env = os.environ.copy()
    env["APP_DIR"] = target
    proc = subprocess.Popen([WORKER], env=env)
    time.sleep(0.3)
    assert proc.poll() is None, "service_worker did not start."
    return proc, target


def test_app_data_directory_exists():
    assert os.path.isdir(APP_DATA_DIR), f"Directory {APP_DATA_DIR} does not exist."


def test_trigger_worker_exports_app_dir():
    assert os.path.isfile(TRIGGER_SCRIPT), f"{TRIGGER_SCRIPT} does not exist."
    with open(TRIGGER_SCRIPT, "r") as f:
        content = f.read()
    assert "APP_DIR=/home/user/app_data" in content, f"{TRIGGER_SCRIPT} does not set APP_DIR correctly."


def test_monitor_script_exists_and_executable():
    assert os.path.isfile(MONITOR_SCRIPT), f"{MONITOR_SCRIPT} does not exist."
    st = os.stat(MONITOR_SCRIPT)
    assert st.st_mode & stat.S_IXUSR, f"{MONITOR_SCRIPT} is not executable."


def test_trigger_worker_execution():
    clean_app_data()
    if os.path.exists(HOME_DATA_LOG):
        os.remove(HOME_DATA_LOG)

    subprocess.run(["env", "-i", "bash", TRIGGER_SCRIPT], check=True)
    deadline = time.time() + 3
    while time.time() < deadline and not os.path.exists(APP_DATA_LOG):
        time.sleep(0.1)

    assert not os.path.exists(HOME_DATA_LOG), f"Data log should not be in /home/user/. Found {HOME_DATA_LOG}."
    assert os.path.exists(APP_DATA_LOG), f"Data log was not written to {APP_DATA_LOG}."
    kill_workers()


def test_monitor_script_under_quota():
    clean_app_data()
    subprocess.run(["bash", MONITOR_SCRIPT], check=True)

    assert os.path.isfile(ALERT_LOG), f"{ALERT_LOG} was not created."
    with open(ALERT_LOG, "r") as f:
        alert_content = f.read().strip()
    assert alert_content == "OK", f"Expected 'OK' in {ALERT_LOG}, got '{alert_content}'."


def test_monitor_script_over_quota():
    clean_app_data()
    subprocess.run(["env", "-i", "bash", TRIGGER_SCRIPT], check=True)
    time.sleep(0.5)

    large_file = os.path.join(APP_DATA_DIR, "large_file.dat")
    with open(large_file, "wb") as f:
        f.write(b"\0" * 2048)

    subprocess.run(["bash", MONITOR_SCRIPT], check=True)

    assert os.path.isfile(ALERT_LOG), f"{ALERT_LOG} was not created."
    with open(ALERT_LOG, "r") as f:
        alert_content = f.read().strip()
    assert alert_content == "QUOTA EXCEEDED", f"Expected 'QUOTA EXCEEDED' in {ALERT_LOG}, got '{alert_content}'."
    wait_for_no_workers()


def test_monitor_uses_total_directory_size_with_unpredictable_paths():
    clean_app_data()
    first_dir = os.path.join(APP_DATA_DIR, "." + secrets.token_hex(7))
    second_dir = os.path.join(APP_DATA_DIR, secrets.token_hex(9))
    os.makedirs(first_dir)
    os.makedirs(second_dir)
    first = os.path.join(first_dir, secrets.token_hex(8) + ".bin")
    second = os.path.join(second_dir, secrets.token_hex(8) + ".bin")
    with open(first, "wb") as f:
        f.write(os.urandom(600))
    with open(second, "wb") as f:
        f.write(os.urandom(600))

    assert os.path.getsize(first) <= 1024 and os.path.getsize(second) <= 1024
    assert directory_bytes() > 1024
    proc, target = start_stable_worker()
    try:
        assert run_monitor() == "QUOTA EXCEEDED"
        wait_for_no_workers()
        proc.wait(timeout=2)
    finally:
        if proc.poll() is None:
            proc.kill()
        shutil.rmtree(target, ignore_errors=True)


def test_monitor_strict_1024_byte_boundary_on_random_name():
    clean_app_data()
    path = os.path.join(APP_DATA_DIR, secrets.token_hex(12) + ".dat")
    with open(path, "wb"):
        pass

    # Adjust the file so GNU du reports exactly 1024 bytes for the directory.
    for _ in range(5):
        total = directory_bytes()
        if total == 1024:
            break
        new_size = os.path.getsize(path) + (1024 - total)
        assert new_size >= 0, "Test environment cannot represent an under-quota directory."
        with open(path, "r+b") as f:
            f.truncate(new_size)
    assert directory_bytes() == 1024
    assert run_monitor() == "OK"

    with open(path, "ab") as f:
        f.write(b"X")
    assert directory_bytes() == 1025

    proc, target = start_stable_worker()
    try:
        assert run_monitor() == "QUOTA EXCEEDED"
        wait_for_no_workers()
        proc.wait(timeout=2)
    finally:
        if proc.poll() is None:
            proc.kill()
        shutil.rmtree(target, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
