#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import re
import shutil
import signal
import subprocess
import time


def packet_lines():
    path = "/home/user/net.log"
    if not os.path.exists(path):
        return []
    with open(path, "r", errors="replace") as f:
        return [line for line in f if "[PACKET_OK]" in line]


def workers_in_group(pgid):
    result = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        pid = int(name)
        try:
            if os.getpgid(pid) != pgid:
                continue
            if os.path.samefile(f"/proc/{pid}/exe", "/app/net_worker"):
                result.append(pid)
        except (FileNotFoundError, ProcessLookupError, PermissionError, OSError):
            pass
    return result


def wait_for_worker(pgid, excluded=None, timeout=4.0):
    excluded = set(excluded or [])
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        candidates = [p for p in workers_in_group(pgid) if p not in excluded]
        if candidates:
            return candidates[0]
        time.sleep(0.05)
    return None


def wait_stopped(pid, timeout=1.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with open(f"/proc/{pid}/status") as f:
                for line in f:
                    if line.startswith("State:"):
                        if "T" in line.split()[1]:
                            return True
                        break
        except FileNotFoundError:
            return False
        time.sleep(0.02)
    return False


def test_supervisor_script_exists_and_executable():
    script_path = "/home/user/supervisor.sh"
    assert os.path.exists(script_path), f"Supervisor script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def test_supervisor_execution_and_metric():
    script_path = "/home/user/supervisor.sh"

    subprocess.run(["pkill", "-9", "net_worker"], capture_output=True)
    for path in ["/home/user/cache", "/home/user/backups"]:
        shutil.rmtree(path, ignore_errors=True)
    for path in ["/home/user/net.log", "/home/user/config.ini"]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    token = os.urandom(32)
    seeded_size = 5242881
    start_wall = int(time.time())
    proc = subprocess.Popen(
        ["bash", script_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        preexec_fn=os.setsid,
    )
    pgid = proc.pid
    deadline = time.monotonic() + 20.0

    initial_worker = None
    replacement_worker = None
    restarted = False
    paused_without_output = False
    resumed_with_output = False
    seed_installed = False

    try:
        initial_worker = wait_for_worker(pgid, timeout=4.0)

        # Inject an unpredictable cache file just over 5 MiB. A compliant
        # supervisor must move and gzip this exact file before it reaches 8 MiB.
        dir_deadline = time.monotonic() + 2.0
        while time.monotonic() < dir_deadline and not os.path.isdir("/home/user/cache"):
            time.sleep(0.05)
        if os.path.isdir("/home/user/cache"):
            tmp = "/home/user/cache/.verifier-seed.tmp"
            with open(tmp, "wb") as f:
                f.write(token)
                f.write(b"B" * (seeded_size - len(token)))
            os.replace(tmp, "/home/user/cache/data.bin")
            seed_installed = True

        # Force a real crash and require a new instance of the exact shipped
        # executable to appear in the supervisor's process group.
        if initial_worker is not None:
            try:
                os.kill(initial_worker, signal.SIGKILL)
            except ProcessLookupError:
                pass
            replacement_worker = wait_for_worker(
                pgid, excluded={initial_worker}, timeout=4.0
            )
            restarted = replacement_worker is not None

        # Stop the real daemon briefly. Its log must stop changing, then start
        # changing again after SIGCONT; a separate fabricated log writer fails.
        observed_worker = replacement_worker or wait_for_worker(pgid, timeout=2.0)
        if observed_worker is not None:
            try:
                os.kill(observed_worker, signal.SIGSTOP)
                if wait_stopped(observed_worker):
                    before = len(packet_lines())
                    time.sleep(0.6)
                    after = len(packet_lines())
                    paused_without_output = before == after
                    os.kill(observed_worker, signal.SIGCONT)
                    resume_deadline = min(deadline, time.monotonic() + 3.0)
                    while time.monotonic() < resume_deadline:
                        if len(packet_lines()) > after:
                            resumed_with_output = True
                            break
                        time.sleep(0.05)
            except ProcessLookupError:
                pass
            finally:
                try:
                    os.kill(observed_worker, signal.SIGCONT)
                except ProcessLookupError:
                    pass

        remaining = deadline - time.monotonic()
        if remaining > 0:
            time.sleep(remaining)
    finally:
        try:
            os.killpg(pgid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        subprocess.run(["pkill", "-9", "net_worker"], capture_output=True)

    end_wall = int(time.time())

    # Original configuration and directory assertions.
    config_path = "/home/user/config.ini"
    backup_path = "/home/user/backups/config.ini.bak"
    assert os.path.exists(config_path), f"Config file {config_path} was not created."
    with open(config_path, "r") as f:
        assert "mode=active" in f.read(), f"Config file {config_path} does not contain 'mode=active'."

    assert os.path.exists(backup_path), f"Backup config file {backup_path} was not created."
    with open(backup_path, "r") as f:
        assert "mode=active" in f.read(), f"Backup config file {backup_path} does not contain 'mode=active'."

    assert os.path.isdir("/home/user/cache"), "/home/user/cache directory does not exist."
    assert os.path.isdir("/home/user/backups"), "/home/user/backups directory does not exist."

    assert initial_worker is not None, "The supervisor never launched /app/net_worker."
    assert restarted, "The supervisor did not restart /app/net_worker after it was killed."
    assert paused_without_output, "net.log changed while the real net_worker process was stopped."
    assert resumed_with_output, "net.log did not resume after the real net_worker process continued."
    assert seed_installed, "The supervisor did not create the cache directory in time."

    # Validate timestamped gzip rotation. One archive must contain the random
    # seeded cache, and another must be a subsequent daemon-produced A-filled
    # cache, proving rotation continued rather than being staged once.
    archives = []
    for name in os.listdir("/home/user/backups"):
        if not re.fullmatch(r"data_.+\.bin\.gz", name):
            continue
        path = os.path.join("/home/user/backups", name)
        try:
            with gzip.open(path, "rb") as f:
                data = f.read(8388609)
        except (OSError, EOFError):
            continue
        archives.append((name, data))

    seeded_archives = [data for _, data in archives if data.startswith(token)]
    assert seeded_archives, "The verifier's >5 MiB cache file was not moved and gzip-compressed."
    assert any(seeded_size <= len(data) < 8388608 for data in seeded_archives), \
        "The seeded cache was not rotated between the 5 MiB threshold and the 8 MiB stall limit."

    daemon_archives = [
        data for _, data in archives
        if 5242880 < len(data) < 8388608 and data and data == b"A" * len(data)
    ]
    assert daemon_archives, "No subsequent daemon-generated cache was rotated and gzip-compressed."

    # Preserve the original packet metric assertion, while also requiring the
    # daemon's exact, run-local output format.
    lines = packet_lines()
    metric = len(lines)
    threshold = 150
    assert metric >= threshold, f"Expected at least {threshold} [PACKET_OK] lines, but got {metric}. The daemon likely stalled or crashed without being restarted properly."

    valid = 0
    for line in lines:
        match = re.fullmatch(r"\[PACKET_OK\] ([0-9]+)\n?", line)
        if match and start_wall - 1 <= int(match.group(1)) <= end_wall + 1:
            valid += 1
    assert valid >= threshold, "The packet log does not contain enough valid run-local net_worker records."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
