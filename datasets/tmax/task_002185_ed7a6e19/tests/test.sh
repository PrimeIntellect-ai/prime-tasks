#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import signal
import subprocess
import time
import pytest


def test_active_routes():
    active_routes_path = "/home/user/config/active_routes.txt"
    assert os.path.isfile(active_routes_path), f"File {active_routes_path} does not exist."

    with open(active_routes_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_routes = [
        "10.0.0.0 192.168.1.1 eth0",
        "192.168.2.0 0.0.0.0 tun1",
        "10.10.10.0 10.10.10.1 tun0"
    ]

    assert lines == expected_routes, f"Parsed routes in {active_routes_path} do not match the expected valid routes."


def test_log_rotator_behavior():
    rotator_script = "/home/user/scripts/log-rotator.sh"
    log_file = "/home/user/monitor/network.log"

    assert os.path.isfile(rotator_script), f"Script {rotator_script} does not exist."
    assert os.access(rotator_script, os.X_OK), f"Script {rotator_script} is not executable."

    def write_lines(n):
        with open(log_file, "w") as f:
            for i in range(n):
                f.write(f"Line {i}\n")

    for ext in ["", ".1", ".2", ".3", ".4"]:
        path = log_file + ext
        if os.path.exists(path):
            os.remove(path)

    # Files with 50 or fewer lines must not be rotated or otherwise modified.
    for n in [random.SystemRandom().randint(0, 49), 50]:
        write_lines(n)
        for index in range(1, 4):
            with open(f"{log_file}.{index}", "w") as f:
                f.write(f"old-{index}\n")

        inode_before = os.stat(log_file).st_ino
        with open(log_file, "rb") as f:
            log_before = f.read()
        old_before = {}
        for index in range(1, 4):
            with open(f"{log_file}.{index}", "rb") as f:
                old_before[index] = f.read()

        subprocess.run([rotator_script], check=True)

        assert os.stat(log_file).st_ino == inode_before, "network.log was replaced even though rotation was not required."
        with open(log_file, "rb") as f:
            assert f.read() == log_before, f"network.log was modified with only {n} lines."
        for index in range(1, 4):
            with open(f"{log_file}.{index}", "rb") as f:
                assert f.read() == old_before[index], f"network.log.{index} was modified without rotation."
        assert not os.path.exists(log_file + ".4"), "network.log.4 should not be created."

    for ext in ["", ".1", ".2", ".3", ".4"]:
        path = log_file + ext
        if os.path.exists(path):
            os.remove(path)

    # Test 1: 55 lines, should rotate
    write_lines(55)
    subprocess.run([rotator_script], check=True)

    assert os.path.getsize(log_file) == 0, "Original network.log was not truncated to 0 bytes."
    assert os.path.isfile(log_file + ".1"), "network.log.1 was not created."
    with open(log_file + ".1", "r") as f:
        assert len(f.readlines()) == 55, "network.log.1 does not contain the expected 55 lines."

    # Test 2: 52 lines, should rotate and shift
    write_lines(52)
    subprocess.run([rotator_script], check=True)

    assert os.path.getsize(log_file) == 0, "Original network.log was not truncated to 0 bytes."
    with open(log_file + ".1", "r") as f:
        assert len(f.readlines()) == 52, "network.log.1 does not contain the expected 52 lines."
    with open(log_file + ".2", "r") as f:
        assert len(f.readlines()) == 55, "network.log.2 does not contain the expected 55 lines."

    # Test 3: 51 lines, should rotate and shift
    write_lines(51)
    subprocess.run([rotator_script], check=True)

    assert os.path.getsize(log_file) == 0, "Original network.log was not truncated to 0 bytes."
    with open(log_file + ".1", "r") as f:
        assert len(f.readlines()) == 51, "network.log.1 does not contain the expected 51 lines."
    with open(log_file + ".3", "r") as f:
        assert len(f.readlines()) == 55, "network.log.3 does not contain the expected 55 lines."

    # Test 4: 53 lines, should rotate, shift, and drop .4
    write_lines(53)
    subprocess.run([rotator_script], check=True)

    assert os.path.getsize(log_file) == 0, "Original network.log was not truncated to 0 bytes."
    with open(log_file + ".1", "r") as f:
        assert len(f.readlines()) == 53, "network.log.1 does not contain the expected 53 lines."
    with open(log_file + ".3", "r") as f:
        assert len(f.readlines()) == 52, "network.log.3 does not contain the expected 52 lines."
    assert not os.path.exists(log_file + ".4"), "network.log.4 should not exist (only keep 3 old versions)."


def test_net_monitor_behavior():
    monitor_script = "/home/user/scripts/net-monitor.sh"

    assert os.path.isfile(monitor_script), f"Script {monitor_script} does not exist."
    assert os.access(monitor_script, os.X_OK), f"Script {monitor_script} is not executable."

    # Kill any existing dummy-service.sh and net-monitor.sh
    subprocess.run(["pkill", "-f", "dummy-service.sh"])
    subprocess.run(["pkill", "-f", "net-monitor.sh"])

    # Start net-monitor.sh in the background
    monitor_proc = subprocess.Popen([monitor_script], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    try:
        # Wait for monitor to start the service
        time.sleep(2)

        # Check if dummy-service.sh is running
        pgrep = subprocess.run(["pgrep", "-f", "dummy-service.sh"], capture_output=True, text=True)
        assert pgrep.returncode == 0 and pgrep.stdout.strip() != "", "dummy-service.sh was not started by net-monitor.sh"

        # Kill it to see if it gets restarted
        subprocess.run(["pkill", "-f", "dummy-service.sh"])

        # Wait for monitor to restart the service
        time.sleep(2)

        pgrep = subprocess.run(["pgrep", "-f", "dummy-service.sh"], capture_output=True, text=True)
        assert pgrep.returncode == 0 and pgrep.stdout.strip() != "", "dummy-service.sh was not restarted by net-monitor.sh after being killed."

    finally:
        monitor_proc.terminate()
        monitor_proc.wait()
        subprocess.run(["pkill", "-f", "dummy-service.sh"])
        subprocess.run(["pkill", "-f", "net-monitor.sh"])


def test_net_monitor_status_cadence_messages_and_no_duplicates():
    monitor_script = "/home/user/scripts/net-monitor.sh"
    service_script = "/home/user/scripts/dummy-service.sh"
    launches_file = "/tmp/dummy-service-launches"

    assert os.path.isfile(monitor_script), f"Script {monitor_script} does not exist."
    assert os.access(monitor_script, os.X_OK), f"Script {monitor_script} is not executable."

    with open(service_script, "rb") as f:
        original_service = f.read()
    original_mode = os.stat(service_script).st_mode

    def launch_pids():
        if not os.path.exists(launches_file):
            return []
        with open(launches_file, "r") as f:
            return [int(line.strip()) for line in f if line.strip()]

    def wait_for_launches(count, timeout):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            pids = launch_pids()
            if len(pids) >= count:
                return pids
            time.sleep(0.02)
        return launch_pids()

    def stop_monitor(proc):
        if proc is None or proc.poll() is not None:
            return proc.communicate(timeout=1) if proc is not None else ("", "")
        proc.terminate()
        try:
            return proc.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            return proc.communicate(timeout=2)

    monitor_proc = None
    manual_service = None
    try:
        subprocess.run(["pkill", "-f", "dummy-service.sh"])
        subprocess.run(["pkill", "-f", "net-monitor.sh"])

        with open(service_script, "w") as f:
            f.write("#!/bin/bash\n")
            f.write(f"echo $$ >> {launches_file}\n")
            f.write("while true; do sleep 0.1; done\n")
        os.chmod(service_script, 0o755)

        # A service that is already running must not be launched again.
        if os.path.exists(launches_file):
            os.remove(launches_file)
        manual_service = subprocess.Popen([service_script], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        assert len(wait_for_launches(1, 1.0)) == 1, "Instrumented dummy service did not start."

        monitor_proc = subprocess.Popen(
            [monitor_script], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        time.sleep(2.3)
        assert monitor_proc.poll() is None, "net-monitor.sh exited instead of running in an infinite loop."
        assert len(launch_pids()) == 1, "net-monitor.sh launched duplicate services while one was already running."
        stdout, _ = stop_monitor(monitor_proc)
        monitor_proc = None
        assert "Restarted dummy-service" not in stdout, "Monitor reported a restart while the service was already running."

        os.kill(manual_service.pid, signal.SIGKILL)
        manual_service.wait(timeout=2)
        manual_service = None

        # After launching a missing service, killing it immediately should cause
        # another launch on the next approximately one-second status check.
        os.remove(launches_file)
        monitor_proc = subprocess.Popen(
            [monitor_script], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        first = wait_for_launches(1, 1.0)
        assert len(first) == 1, "dummy-service.sh was not started by net-monitor.sh"
        os.kill(first[0], signal.SIGKILL)

        killed_at = time.monotonic()
        second = wait_for_launches(2, 1.55)
        restart_delay = time.monotonic() - killed_at
        assert len(second) >= 2, "dummy-service.sh was not restarted on the next status check."
        assert restart_delay <= 1.55, "net-monitor.sh did not check service status at approximately one-second intervals."

        pgrep = subprocess.run(["pgrep", "-f", "dummy-service.sh"], capture_output=True, text=True)
        assert pgrep.returncode == 0 and pgrep.stdout.strip() != "", "dummy-service.sh was not restarted by net-monitor.sh after being killed."

        time.sleep(1.3)
        assert monitor_proc.poll() is None, "net-monitor.sh exited instead of continuing to supervise the service."
        assert len(launch_pids()) == 2, "net-monitor.sh repeatedly launched duplicate dummy services."

        stdout, _ = stop_monitor(monitor_proc)
        monitor_proc = None
        assert stdout.count("Restarted dummy-service") >= 2, "net-monitor.sh did not echo the required restart message for each launch."

    finally:
        if monitor_proc is not None:
            stop_monitor(monitor_proc)
        if manual_service is not None and manual_service.poll() is None:
            manual_service.kill()
            manual_service.wait()
        subprocess.run(["pkill", "-f", "dummy-service.sh"])
        subprocess.run(["pkill", "-f", "net-monitor.sh"])
        with open(service_script, "wb") as f:
            f.write(original_service)
        os.chmod(service_script, original_mode)
        if os.path.exists(launches_file):
            os.remove(launches_file)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
