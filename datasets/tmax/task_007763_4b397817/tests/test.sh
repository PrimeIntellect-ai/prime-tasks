#!/bin/bash
mkdir -p /logs/verifier
status=0

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os


def test_migration_fstab_exists_and_content():
    fstab_path = "/home/user/migration_fstab.txt"
    assert os.path.isfile(fstab_path), f"File {fstab_path} does not exist."

    with open(fstab_path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "service_v1 /home/user/deployments/v1 8001 0",
        "service_v2 /home/user/deployments/v2 8002 3",
        "service_v3 /home/user/deployments/v3 8003 6"
    ]

    lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert lines == expected_lines, f"Contents of {fstab_path} do not match the expected configuration."


def test_deployment_directories_and_info():
    services = ["v1", "v2", "v3"]
    for i, version in enumerate(services, 1):
        dir_path = f"/home/user/deployments/{version}"
        assert os.path.isdir(dir_path), f"Directory {dir_path} does not exist."

        info_path = os.path.join(dir_path, "info.txt")
        assert os.path.isfile(info_path), f"File {info_path} does not exist."

        with open(info_path, "r") as f:
            content = f.read().strip()

        expected_content = f"service_v{i}"
        assert content == expected_content, f"Content of {info_path} should be '{expected_content}', but got '{content}'."


def test_live_service_symlink():
    symlink_path = "/home/user/live_service"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."

    target = os.readlink(symlink_path)
    expected_target = "/home/user/deployments/v3"
    assert target == expected_target, f"Symlink {symlink_path} points to {target}, expected {expected_target}."


def test_migration_events_log():
    log_path = "/home/user/migration_events.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "DEPLOYED service_v1 TO /home/user/deployments/v1 ON PORT 8001",
        "DEPLOYED service_v2 TO /home/user/deployments/v2 ON PORT 8002",
        "DEPLOYED service_v3 TO /home/user/deployments/v3 ON PORT 8003"
    ]

    lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert lines == expected_lines, f"Contents of {log_path} do not match the expected deployment logs."


def test_deploy_monitor_c_exists():
    c_path = "/home/user/deploy_monitor.c"
    assert os.path.isfile(c_path), f"File {c_path} does not exist."

    with open(c_path, "r") as f:
        content = f.read()

    assert "#include" in content, f"{c_path} does not appear to contain valid C code."


def test_monitor_binary_and_mock_script_exist():
    binary = "/home/user/deploy_monitor"
    script = "/home/user/start_mocks.sh"
    assert os.path.isfile(binary), f"File {binary} does not exist."
    assert os.access(binary, os.X_OK), f"{binary} is not executable."
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{binary} is not an ELF executable."
    assert os.path.isfile(script), f"File {script} does not exist."
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || status=1

if [ "$status" -eq 0 ]; then
    bash -n /home/user/start_mocks.sh || status=1
fi

# Rebuild the required artifact from the submitted source, then exercise that
# exact output rather than trusting the fabricated final filesystem state.
if [ "$status" -eq 0 ]; then
    gcc -O2 /home/user/deploy_monitor.c -o /home/user/deploy_monitor || status=1
fi

cat << 'BEHAVIOR_EOF' > /tmp/test_behavior.py
import os
import signal
import socket
import subprocess
import time

FSTAB = "/home/user/migration_fstab.txt"
LOG = "/home/user/migration_events.log"
LINK = "/home/user/live_service"
MONITOR = "/home/user/deploy_monitor"
MOCKS = "/home/user/start_mocks.sh"
TARGETS = [f"/home/user/deployments/v{i}" for i in (1, 2, 3)]


def free_ports(count):
    sockets = []
    try:
        for _ in range(count):
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.bind(("127.0.0.1", 0))
            sockets.append(s)
        return [s.getsockname()[1] for s in sockets]
    finally:
        for s in sockets:
            s.close()


def lines():
    try:
        with open(LOG) as f:
            return [x.strip() for x in f if x.strip()]
    except FileNotFoundError:
        return []


def remove_state():
    try:
        os.unlink(LINK)
    except FileNotFoundError:
        pass
    try:
        os.unlink(LOG)
    except FileNotFoundError:
        pass


def wait_for_line_count(n, deadline):
    while time.monotonic() < deadline:
        current = lines()
        if len(current) >= n:
            return current
        time.sleep(0.1)
    raise AssertionError(f"Timed out waiting for {n} deployment entries; got {lines()}")


with open(FSTAB, "rb") as f:
    saved_fstab = f.read()
saved_log = open(LOG, "rb").read() if os.path.isfile(LOG) else None
saved_link = os.readlink(LINK) if os.path.islink(LINK) else None

monitor = None
mocks = None
try:
    ports = free_ports(3)
    delays = [0, 3, 6]
    config = "".join(
        f"service_v{i} {TARGETS[i-1]} {ports[i-1]} {delays[i-1]}\n"
        for i in (1, 2, 3)
    )
    with open(FSTAB, "w") as f:
        f.write(config)
    remove_state()

    # With all selected ports closed, a real health-checking monitor must wait.
    monitor = subprocess.Popen(
        [MONITOR], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    time.sleep(2.2)
    assert monitor.poll() is None, "Monitor exited before any service became healthy"
    assert lines() == [], "Monitor deployed a service while every configured port was closed"
    assert not os.path.lexists(LINK), "Monitor created live_service while every configured port was closed"

    started = time.monotonic()
    mocks = subprocess.Popen(
        ["bash", MOCKS], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )

    expected = [
        f"DEPLOYED service_v{i} TO {TARGETS[i-1]} ON PORT {ports[i-1]}"
        for i in (1, 2, 3)
    ]

    first = wait_for_line_count(1, started + 2.5)
    assert first == expected[:1], f"First rolling stage was incorrect: {first}"
    assert os.path.islink(LINK) and os.readlink(LINK) == TARGETS[0]

    # service_v2 has a three-second startup delay and must not deploy early.
    while time.monotonic() < started + 2.5:
        time.sleep(0.05)
    assert lines() == expected[:1], "A delayed service was deployed before its listener started"

    second = wait_for_line_count(2, started + 5.5)
    assert second == expected[:2], f"Second rolling stage was incorrect: {second}"
    assert os.path.islink(LINK) and os.readlink(LINK) == TARGETS[1]

    # service_v3 has a six-second startup delay and must not deploy early.
    while time.monotonic() < started + 5.5:
        time.sleep(0.05)
    assert lines() == expected[:2], "The final delayed service was deployed before its listener started"

    final = wait_for_line_count(3, started + 9.5)
    assert final == expected, f"Rolling deployment history was incorrect: {final}"
    assert os.path.islink(LINK) and os.readlink(LINK) == TARGETS[2]

    monitor.wait(timeout=3)
    assert monitor.returncode == 0, f"Monitor did not exit cleanly: {monitor.returncode}"
finally:
    for proc in (monitor, mocks):
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    time.sleep(0.2)
    for proc in (monitor, mocks):
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

    with open(FSTAB, "wb") as f:
        f.write(saved_fstab)
    remove_state()
    if saved_log is not None:
        with open(LOG, "wb") as f:
            f.write(saved_log)
    if saved_link is not None:
        os.symlink(saved_link, LINK)
BEHAVIOR_EOF

if [ "$status" -eq 0 ]; then
    timeout 25s python3 /tmp/test_behavior.py 2>&1 || status=1
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
