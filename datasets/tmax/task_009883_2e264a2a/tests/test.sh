#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import threading
import time
import uuid

import pytest


def read_pid():
    pid_file = "/home/user/exporter.pid"
    assert os.path.isfile(pid_file), f"PID file {pid_file} is missing."
    with open(pid_file, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file {pid_file} does not contain a valid PID."
    return int(pid_str)


def process_running(pid):
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    try:
        with open(f"/proc/{pid}/stat", "r") as f:
            return f.read().split()[2] != "Z"
    except OSError:
        return False


def metric_lines(path="/home/user/dashboard/metrics.prom"):
    with open(path, "r") as f:
        return f.read().splitlines()


def wait_for_lines(expected, timeout=4.0):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            last = metric_lines()
            if last == expected:
                return
        except FileNotFoundError:
            pass
        time.sleep(0.05)
    pytest.fail(f"metrics.prom did not become the expected complete snapshot; last value: {last!r}")


def test_deploy_script_executable():
    deploy_script = "/home/user/deploy.sh"
    assert os.path.isfile(deploy_script), f"{deploy_script} does not exist or is not a file."
    assert os.access(deploy_script, os.X_OK), f"{deploy_script} is not executable."


def test_exporter_running():
    pid = read_pid()
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} (from /home/user/exporter.pid) is not running.")


def test_metrics_prom():
    metrics_file = "/home/user/dashboard/metrics.prom"
    for _ in range(30):
        if os.path.isfile(metrics_file):
            break
        time.sleep(0.1)

    assert os.path.isfile(metrics_file), f"Metrics file {metrics_file} is missing."
    with open(metrics_file, "r") as f:
        content = f.read()

    expected_lines = [
        'mount_active{path="/home/user/mounts/app_data"} 1',
        'mount_active{path="/home/user/mounts/backup"} 1',
        'mount_active{path="/home/user/mounts/offline"} 0'
    ]
    for line in expected_lines:
        assert line in content, f"Expected metric '{line}' not found in {metrics_file}"


def test_idempotency():
    old_pid = read_pid()
    deploy_script = "/home/user/deploy.sh"
    result = subprocess.run([deploy_script], capture_output=True, text=True)
    assert result.returncode == 0, f"{deploy_script} failed on second run. Error: {result.stderr}"

    time.sleep(0.5)
    new_pid = read_pid()
    assert old_pid != new_pid, "PID did not change after redeploy. Service lifecycle failed (not restarted)."

    try:
        os.kill(new_pid, 0)
    except OSError:
        pytest.fail(f"New process with PID {new_pid} is not running after redeploy.")

    deadline = time.monotonic() + 2.0
    while process_running(old_pid) and time.monotonic() < deadline:
        time.sleep(0.05)
    assert not process_running(old_pid), "The previous exporter process was not terminated during redeploy."


def test_real_c_exporter_dynamic_behavior_and_atomic_updates():
    source = "/home/user/exporter.c"
    binary = "/home/user/exporter"
    deploy = "/home/user/deploy.sh"
    config = "/home/user/dashboard_fstab.conf"
    metrics = "/home/user/dashboard/metrics.prom"

    assert os.path.isfile(source), f"{source} is missing."
    syntax = subprocess.run(
        ["gcc", "-fsyntax-only", source], capture_output=True, text=True
    )
    assert syntax.returncode == 0, f"exporter.c is not valid C: {syntax.stderr}"

    token = uuid.uuid4().hex
    base = f"/home/user/mounts/verify_{token}"
    paths = [f"{base}_{i}" for i in range(4)]
    os.makedirs(paths[0])
    os.makedirs(paths[2])

    with open(config, "w") as f:
        f.write("# dynamically generated verifier configuration\n\n")
        for i, path in enumerate(paths):
            f.write(f"/dev/verify{i} {path} ext4 defaults 0 0\n")

    old_pid = read_pid()
    if os.path.lexists(binary):
        os.unlink(binary)

    result = subprocess.run([deploy], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, f"deploy.sh failed after exporter removal: {result.stderr}"
    assert os.path.isfile(binary), "deploy.sh did not recreate /home/user/exporter."
    assert os.access(binary, os.X_OK), "The rebuilt exporter is not executable."
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The deployed exporter is not a compiled ELF executable."

    new_pid = read_pid()
    assert new_pid != old_pid, "Redeployment did not replace the prior process."
    assert process_running(new_pid), "The newly deployed exporter is not running."
    assert os.path.samefile(f"/proc/{new_pid}/exe", binary), \
        "The PID file does not identify the deployed exporter executable."

    deadline = time.monotonic() + 2.0
    while process_running(old_pid) and time.monotonic() < deadline:
        time.sleep(0.05)
    assert not process_running(old_pid), "The old exporter remained alive after dynamic redeployment."

    initial = [
        f'mount_active{{path="{paths[0]}"}} 1',
        f'mount_active{{path="{paths[1]}"}} 0',
        f'mount_active{{path="{paths[2]}"}} 1',
        f'mount_active{{path="{paths[3]}"}} 0',
    ]
    wait_for_lines(initial)

    changed = initial.copy()
    changed[0] = f'mount_active{{path="{paths[0]}"}} 0'
    accepted = {tuple(initial), tuple(changed)}
    invalid_reads = []
    stop = threading.Event()

    def sample_metrics():
        while not stop.is_set():
            try:
                lines = tuple(metric_lines(metrics))
                if lines not in accepted:
                    invalid_reads.append(lines)
                    stop.set()
                    return
            except FileNotFoundError:
                invalid_reads.append(("<missing>",))
                stop.set()
                return
            time.sleep(0.002)

    sampler = threading.Thread(target=sample_metrics, daemon=True)
    sampler.start()
    shutil.rmtree(paths[0])
    wait_for_lines(changed, timeout=4.0)
    time.sleep(0.25)
    stop.set()
    sampler.join(timeout=1.0)
    assert not invalid_reads, f"Observed a missing or partial metrics snapshot: {invalid_reads[:1]}"

    # With an atomic temporary-file rename, each periodic publication replaces
    # metrics.prom with a new inode. It must continue publishing once per second
    # even while statuses remain unchanged.
    start = time.monotonic()
    st = os.stat(metrics)
    last_key = (st.st_ino, st.st_mtime_ns)
    changes = [(start, st.st_ino, st.st_mtime_ns)]
    while time.monotonic() - start < 3.8:
        assert metric_lines(metrics) == changed, "Periodic output became incomplete or malformed."
        st = os.stat(metrics)
        key = (st.st_ino, st.st_mtime_ns)
        if key != last_key:
            changes.append((time.monotonic(), st.st_ino, st.st_mtime_ns))
            last_key = key
        time.sleep(0.02)

    assert len(changes) >= 4, "metrics.prom was not republished approximately every second."
    assert changes[-1][0] - start >= 2.5, "Exporter stopped updating metrics.prom continuously."
    gaps = [changes[i][0] - changes[i - 1][0] for i in range(1, len(changes))]
    assert max(gaps) <= 1.7, f"Metric publication interval was too long: {gaps!r}"
    assert any(changes[i][1] != changes[i - 1][1] for i in range(1, len(changes))), \
        "metrics.prom was updated in place instead of being atomically replaced."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
