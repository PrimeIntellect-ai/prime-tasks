#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import subprocess
import time

STATUS_FILE = '/home/user/status.json'
PIDS_FILE = '/home/user/monitored_pids.txt'
PROJECT_DIR = '/home/user/health_monitor'
BINARY = '/home/user/health_monitor/target/release/health_monitor'


def test_status_json_exists_and_valid():
    """Verify that status.json exists and contains valid JSON."""
    assert os.path.exists(STATUS_FILE), f"{STATUS_FILE} does not exist."

    with open(STATUS_FILE, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{STATUS_FILE} does not contain valid JSON."

    assert isinstance(data, dict), f"JSON in {STATUS_FILE} must be an object (dict)."


def test_status_json_content():
    """Verify that the JSON correctly identifies active and inactive PIDs."""
    assert os.path.exists(PIDS_FILE), f"{PIDS_FILE} is missing."
    with open(PIDS_FILE, 'r') as f:
        pids = [line.strip() for line in f if line.strip()]

    with open(STATUS_FILE, 'r') as f:
        data = json.load(f)

    for pid in pids:
        assert pid in data, f"PID {pid} is missing from {STATUS_FILE}."

        is_active = os.path.isdir(f"/proc/{pid}")
        expected_status = "active" if is_active else "inactive"

        assert data[pid] == expected_status, f"PID {pid} should be '{expected_status}', but got '{data[pid]}'."


def test_health_monitor_running():
    """Verify that the health_monitor process is running in the background."""
    try:
        ps_output = subprocess.check_output(['ps', '-e', '-o', 'comm='], text=True)
    except subprocess.CalledProcessError:
        assert False, "Failed to execute 'ps' command."

    processes = [line.strip() for line in ps_output.splitlines()]
    assert "health_monitor" in processes, "The 'health_monitor' process is not running in the background."


def wait_for_json(expected, timeout=3.5):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            with open(STATUS_FILE, 'r') as f:
                last = json.load(f)
            if last == expected:
                return
        except (OSError, json.JSONDecodeError):
            pass
        time.sleep(0.05)
    assert last == expected, f"Daemon did not rewrite {STATUS_FILE} with the expected data; last value was {last!r}"


def wait_for_mtime_change(previous, timeout=2.2):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            current = os.stat(STATUS_FILE).st_mtime_ns
            if current != previous:
                return current, time.monotonic()
        except FileNotFoundError:
            pass
        time.sleep(0.03)
    assert False, f"{STATUS_FILE} was not overwritten within {timeout} seconds"


def stop_existing_health_monitors():
    victims = []
    for name in os.listdir('/proc'):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        try:
            with open(f'/proc/{name}/comm', 'r') as f:
                if f.read().strip() == 'health_monitor':
                    victims.append(int(name))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.25)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def unused_pid(start):
    pid = start
    while os.path.exists(f'/proc/{pid}'):
        pid += 1
    return str(pid)


def test_compiled_rust_daemon_reacts_and_rewrites_periodically():
    """Build and exercise the submitted Rust binary, including repeated updates."""
    assert os.path.isfile(os.path.join(PROJECT_DIR, 'Cargo.toml')), "Cargo.toml is missing."
    assert os.path.isfile(os.path.join(PROJECT_DIR, 'src', 'main.rs')), "src/main.rs is missing."

    stop_existing_health_monitors()
    subprocess.run(
        ['cargo', 'build', '--release', '--offline'],
        cwd=PROJECT_DIR,
        check=True,
        timeout=120,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert os.path.isfile(BINARY), "The release health_monitor binary was not produced."
    assert os.access(BINARY, os.X_OK), "The release health_monitor binary is not executable."
    with open(BINARY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "The release artifact is not a compiled executable."

    with open(PIDS_FILE, 'r') as f:
        original_pids = f.read()

    proc = subprocess.Popen(
        [BINARY],
        cwd=PROJECT_DIR,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    try:
        time.sleep(0.15)
        assert proc.poll() is None, "The compiled health_monitor binary exited."
        assert os.path.realpath(f'/proc/{proc.pid}/exe') == os.path.realpath(BINARY), "The running process is not the compiled release binary."

        missing1 = unused_pid(7000000)
        first_pids = [str(os.getpid()), missing1]
        with open(PIDS_FILE, 'w') as f:
            f.write('\n'.join(first_pids) + '\n')
        wait_for_json({first_pids[0]: 'active', first_pids[1]: 'inactive'})

        missing2 = unused_pid(int(missing1) + 1)
        second_pids = [str(os.getppid()), missing2]
        with open(PIDS_FILE, 'w') as f:
            f.write('\n'.join(second_pids) + '\n')
        expected = {second_pids[0]: 'active', second_pids[1]: 'inactive'}
        wait_for_json(expected)

        # Stopping this exact executable must stop rewrites, proving that the
        # tested binary, rather than an unrelated named process, owns the file.
        os.kill(proc.pid, signal.SIGSTOP)
        time.sleep(0.2)
        paused_mtime = os.stat(STATUS_FILE).st_mtime_ns
        time.sleep(1.35)
        assert os.stat(STATUS_FILE).st_mtime_ns == paused_mtime, "Another process is rewriting status.json instead of the tested binary."
        os.kill(proc.pid, signal.SIGCONT)

        # Synchronize once after resuming, then require two approximately
        # one-second periodic overwrites while the input remains unchanged.
        mtime, _ = wait_for_mtime_change(paused_mtime)
        mtime, timestamp = wait_for_mtime_change(mtime)
        for _ in range(2):
            mtime, next_timestamp = wait_for_mtime_change(mtime)
            interval = next_timestamp - timestamp
            assert 0.60 <= interval <= 1.80, f"status.json rewrite interval was {interval:.2f}s, not approximately 1 second."
            timestamp = next_timestamp
            with open(STATUS_FILE, 'r') as f:
                assert json.load(f) == expected

        assert proc.poll() is None, "The compiled daemon did not remain running."
    finally:
        try:
            os.kill(proc.pid, signal.SIGCONT)
        except ProcessLookupError:
            pass
        with open(PIDS_FILE, 'w') as f:
            f.write(original_pids)
        if proc.poll() is None:
            deadline = time.monotonic() + 2.0
            while time.monotonic() < deadline:
                try:
                    with open(STATUS_FILE, 'r') as f:
                        restored = json.load(f)
                    original_keys = {line.strip() for line in original_pids.splitlines() if line.strip()}
                    if original_keys.issubset(restored.keys()):
                        break
                except (OSError, json.JSONDecodeError):
                    pass
                time.sleep(0.05)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
