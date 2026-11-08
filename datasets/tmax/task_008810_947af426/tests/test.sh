#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import time
import uuid
import pytest

LOGICAL_CLUSTER_DIR = "/home/user/logical_cluster"
RAW_STORAGE_DIR = "/home/user/raw_storage"
CONF_FILE = "/home/user/capacity.conf"
DAEMON_SCRIPT = "/home/user/capacity-daemon.sh"
INIT_SCRIPT = "/home/user/cluster-init.sh"
PID_FILE = "/home/user/daemon.pid"
ALERT_LOG = "/home/user/capacity_alerts.log"
EXPECTED_CONFIG_LINES = [
    "THRESHOLD_BYTES=15000000",
    "ALERT_LOG=/home/user/capacity_alerts.log",
]


def test_logical_cluster_symlinks():
    assert os.path.isdir(LOGICAL_CLUSTER_DIR), f"Directory {LOGICAL_CLUSTER_DIR} does not exist."

    expected_links = {
        "vol1": "node_alpha",
        "vol2": "node_beta",
        "vol3": "node_gamma",
        "vol4": "node_delta",
    }

    for link_name, target_node in expected_links.items():
        link_path = os.path.join(LOGICAL_CLUSTER_DIR, link_name)
        assert os.path.islink(link_path), f"{link_path} is not a symlink."

        target_path = os.readlink(link_path)
        expected_abs_target = os.path.join(RAW_STORAGE_DIR, target_node)
        actual_abs_target = os.path.normpath(os.path.join(LOGICAL_CLUSTER_DIR, target_path))
        assert actual_abs_target == expected_abs_target, (
            f"Symlink {link_name} points to {actual_abs_target}, expected {expected_abs_target}."
        )


def test_capacity_conf():
    assert os.path.isfile(CONF_FILE), f"Config file {CONF_FILE} does not exist."
    with open(CONF_FILE, "r") as f:
        content = f.read()

    assert "THRESHOLD_BYTES=15000000" in content, f"{CONF_FILE} missing THRESHOLD_BYTES=15000000"
    assert "ALERT_LOG=/home/user/capacity_alerts.log" in content, (
        f"{CONF_FILE} missing ALERT_LOG=/home/user/capacity_alerts.log"
    )
    assert content.splitlines() == EXPECTED_CONFIG_LINES, (
        f"{CONF_FILE} must contain exactly the instructed two lines."
    )


def test_scripts_executable():
    assert os.path.isfile(DAEMON_SCRIPT), f"{DAEMON_SCRIPT} does not exist."
    assert os.access(DAEMON_SCRIPT, os.X_OK), f"{DAEMON_SCRIPT} is not executable."

    assert os.path.isfile(INIT_SCRIPT), f"{INIT_SCRIPT} does not exist."
    assert os.access(INIT_SCRIPT, os.X_OK), f"{INIT_SCRIPT} is not executable."


def read_pid():
    assert os.path.isfile(PID_FILE), f"PID file {PID_FILE} does not exist."
    with open(PID_FILE, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file {PID_FILE} does not contain a valid integer PID."
    return int(pid_str)


def process_is_running(pid):
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    stat_path = f"/proc/{pid}/stat"
    try:
        with open(stat_path, "r") as f:
            state = f.read().split()[2]
        return state != "Z"
    except (OSError, IndexError):
        return False


def read_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def test_daemon_running():
    pid = read_pid()
    assert process_is_running(pid), f"Process with PID {pid} is not running."

    cmdline_file = f"/proc/{pid}/cmdline"
    if os.path.isfile(cmdline_file):
        cmdline = read_cmdline(pid)
        assert "capacity-daemon.sh" in cmdline or "bash" in cmdline, (
            f"Process {pid} does not seem to be the capacity daemon."
        )


def test_alert_log():
    assert os.path.isfile(ALERT_LOG), (
        f"Alert log {ALERT_LOG} does not exist. Daemon may not have run or logic is incorrect."
    )

    with open(ALERT_LOG, "r") as f:
        content = f.read()

    assert "CRITICAL: Usage at " in content, "Alert log does not contain 'CRITICAL: Usage at '."
    matches = re.findall(r"CRITICAL: Usage at (\d+) bytes", content)
    assert len(matches) > 0, "No correctly formatted alert lines found in the log."
    for match in matches:
        bytes_val = int(match)
        assert bytes_val > 15000000, (
            f"Logged bytes {bytes_val} is not greater than the threshold 15000000."
        )


def active_file_total():
    total = 0
    for name in ("vol1", "vol2", "vol3", "vol4"):
        volume = os.path.realpath(os.path.join(LOGICAL_CLUSTER_DIR, name))
        if os.path.exists(os.path.join(volume, ".offline")):
            continue
        for root, dirs, files in os.walk(volume, followlinks=True):
            for filename in files:
                path = os.path.join(root, filename)
                if os.path.isfile(path):
                    total += os.path.getsize(path)
    return total


def run_init(action):
    result = subprocess.run(
        [INIT_SCRIPT, action],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=8,
    )
    assert result.returncode == 0, (
        f"{INIT_SCRIPT} {action} failed with status {result.returncode}: {result.stderr}"
    )


def stop_and_check():
    old_pid = read_pid()
    run_init("stop")
    assert not os.path.exists(PID_FILE), "stop did not remove the PID file."
    deadline = time.time() + 4
    while time.time() < deadline and process_is_running(old_pid):
        time.sleep(0.1)
    assert not process_is_running(old_pid), "stop did not terminate the daemon process."


def start_and_check():
    run_init("start")
    deadline = time.time() + 3
    pid = None
    while time.time() < deadline:
        if os.path.isfile(PID_FILE):
            try:
                pid = read_pid()
            except AssertionError:
                pid = None
            if pid is not None and process_is_running(pid):
                break
        time.sleep(0.1)
    assert pid is not None and process_is_running(pid), "start did not launch a running daemon."
    cmdline = read_cmdline(pid)
    assert DAEMON_SCRIPT in cmdline, (
        f"PID {pid} is not an execution of {DAEMON_SCRIPT}; cmdline was {cmdline!r}."
    )
    return pid


def clear_alert_log():
    with open(ALERT_LOG, "w"):
        pass


def wait_for_exact_alert(total, minimum_count=1, timeout=6):
    expected = f"CRITICAL: Usage at {total} bytes"
    deadline = time.time() + timeout
    lines = []
    while time.time() < deadline:
        if os.path.isfile(ALERT_LOG):
            with open(ALERT_LOG, "r") as f:
                lines = [line.rstrip("\n") for line in f.readlines()]
            if len(lines) >= minimum_count and all(line == expected for line in lines):
                return
        time.sleep(0.1)
    assert len(lines) >= minimum_count, (
        f"Daemon did not append at least {minimum_count} alert(s) within {timeout} seconds."
    )
    assert all(line == expected for line in lines), (
        f"Alert log must contain only the derived line {expected!r}; got {lines!r}."
    )


def test_daemon_behavior_and_init_lifecycle():
    stop_and_check()

    token = uuid.uuid4().hex
    active_probe = os.path.join(RAW_STORAGE_DIR, "node_alpha", f"active-{token}.bin")
    offline_probe = os.path.join(RAW_STORAGE_DIR, "node_gamma", f"offline-{token}.bin")

    try:
        active_size = 200000 + int.from_bytes(os.urandom(2), "big")
        with open(active_probe, "wb") as f:
            f.truncate(active_size)

        expected_with_active_probe = active_file_total()
        assert expected_with_active_probe > 15000000
        clear_alert_log()
        start_and_check()
        wait_for_exact_alert(expected_with_active_probe, minimum_count=2, timeout=7)

        offline_size = 700000 + int.from_bytes(os.urandom(2), "big")
        with open(offline_probe, "wb") as f:
            f.truncate(offline_size)

        expected_after_offline_probe = active_file_total()
        assert expected_after_offline_probe == expected_with_active_probe, (
            "Verifier setup error: an offline volume affected the derived active total."
        )
        clear_alert_log()
        wait_for_exact_alert(expected_after_offline_probe, minimum_count=2, timeout=7)

        stop_and_check()
    finally:
        for path in (active_probe, offline_probe):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

    final_expected = active_file_total()
    assert final_expected > 15000000
    clear_alert_log()
    start_and_check()
    wait_for_exact_alert(final_expected, minimum_count=1, timeout=7)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
