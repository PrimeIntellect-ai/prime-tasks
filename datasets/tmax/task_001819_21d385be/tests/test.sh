#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PREFLIGHT_EOF' > /tmp/verify_execution.py
import os
import signal
import socket
import subprocess
import time

LAUNCH = "/home/user/launch.sh"
MONITOR = "/home/user/monitor"
LOG = "/home/user/monitor.log"


def listener_pids(port):
    result = subprocess.run(
        ["lsof", "-nP", "-t", f"-iTCP:{port}", "-sTCP:LISTEN"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    return [int(x) for x in result.stdout.split() if x.isdigit()]


def kill_listeners(*ports):
    pids = set()
    for port in ports:
        pids.update(listener_pids(port))
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline:
        if not any(listener_pids(port) for port in ports):
            return
        time.sleep(0.05)
    for port in ports:
        for pid in listener_pids(port):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    time.sleep(0.2)


def port_open(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.15)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
    except FileNotFoundError:
        return []


def is_required_http_server(pid, port):
    args = cmdline(pid)
    return (
        bool(args)
        and "python3" in os.path.basename(args[0])
        and "-m" in args
        and "http.server" in args
        and str(port) in args
        and "--bind" in args
        and "127.0.0.1" in args
    )


def run_and_observe_launch():
    kill_listeners(9001, 9002)
    for path in (LOG, MONITOR):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    started = time.monotonic()
    proc = subprocess.Popen(
        ["runuser", "-u", "user", "--", LAUNCH],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    observed_9001_pid = None
    observed_9002_pid = None
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline and proc.poll() is None:
        pids1 = listener_pids(9001)
        pids2 = listener_pids(9002)
        good1 = [pid for pid in pids1 if is_required_http_server(pid, 9001)]
        good2 = [pid for pid in pids2 if is_required_http_server(pid, 9002)]
        if good1 and good2:
            observed_9001_pid = good1[0]
            observed_9002_pid = good2[0]
            break
        time.sleep(0.05)

    try:
        rc = proc.wait(timeout=20)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
        raise AssertionError("launch.sh did not finish in time")

    elapsed = time.monotonic() - started
    assert rc == 0, f"launch.sh exited with status {rc}"
    assert elapsed >= 1.8, "launch.sh did not perform the required two-second wait"
    assert observed_9001_pid is not None and observed_9002_pid is not None, (
        "launch.sh did not run Python HTTP servers on ports 9001 and 9002 simultaneously"
    )
    assert observed_9001_pid in listener_pids(9001), (
        "the original Python HTTP server on port 9001 did not survive launch.sh"
    )
    assert observed_9002_pid not in listener_pids(9002), (
        "the Python HTTP server on port 9002 was not killed"
    )
    assert os.path.isfile(MONITOR), "launch.sh did not create /home/user/monitor"
    assert os.access(MONITOR, os.X_OK), "/home/user/monitor is not executable"
    with open(MONITOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/monitor is not a compiled ELF executable"


def make_listener(port):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", port))
    sock.listen(8)
    return sock


def run_monitor_with_state(up_ports):
    kill_listeners(9001, 9002)
    try:
        os.remove(LOG)
    except FileNotFoundError:
        pass

    listeners = [make_listener(port) for port in sorted(up_ports)]
    try:
        result = subprocess.run(
            [MONITOR], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5
        )
        assert result.returncode == 0, f"monitor exited with status {result.returncode}"
    finally:
        for sock in listeners:
            sock.close()

    if not os.path.exists(LOG):
        return b""
    with open(LOG, "rb") as f:
        return f.read()


assert os.path.isfile(LAUNCH), f"{LAUNCH} does not exist"
assert os.access(LAUNCH, os.X_OK), f"{LAUNCH} is not executable"

# Execute the submitted setup and verify that both required Python servers really
# coexist before the script removes only the server on port 9002.
run_and_observe_launch()

# Exercise the compiled artifact against independently controlled TCP states.
assert run_monitor_with_state({9001, 9002}) == b"", "monitor logged while both ports were up"
assert run_monitor_with_state({9001}) == b"ALERT: PORT 9002 DOWN\n", (
    "monitor did not correctly detect port 9002 as down"
)
assert run_monitor_with_state({9002}) == b"ALERT: PORT 9001 DOWN\n", (
    "monitor did not correctly detect port 9001 as down"
)

# Re-run the submitted setup so the original required final-state assertions are
# evaluated after genuine execution of launch.sh and monitor.
run_and_observe_launch()
PREFLIGHT_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import socket
import subprocess


def is_port_in_use(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(('127.0.0.1', port)) == 0


def test_files_exist_and_permissions():
    """Check that launch.sh and monitor.c exist, and launch.sh is executable with set -e."""
    launch_sh = "/home/user/launch.sh"
    monitor_c = "/home/user/monitor.c"

    assert os.path.isfile(launch_sh), f"{launch_sh} does not exist."
    assert os.path.isfile(monitor_c), f"{monitor_c} does not exist."
    assert os.access(launch_sh, os.X_OK), f"{launch_sh} is not executable."

    with open(launch_sh, 'r') as f:
        content = f.read()
    assert "set -e" in content, f"{launch_sh} must use 'set -e' for error handling."


def test_monitor_c_headers():
    """Check that monitor.c contains socket programming includes."""
    monitor_c = "/home/user/monitor.c"
    with open(monitor_c, 'r') as f:
        content = f.read()

    assert "sys/socket.h" in content, f"{monitor_c} does not include <sys/socket.h>."
    assert "arpa/inet.h" in content or "netinet/in.h" in content, f"{monitor_c} does not include <arpa/inet.h> or <netinet/in.h>."


def test_port_9001_running():
    """Check that port 9001 is actively listening."""
    assert is_port_in_use(9001), "Port 9001 is not listening. The server should be running."
    result = subprocess.run(
        ["lsof", "-nP", "-t", "-iTCP:9001", "-sTCP:LISTEN"],
        stdout=subprocess.PIPE,
        text=True,
        check=True,
    )
    pids = [pid for pid in result.stdout.split() if pid.isdigit()]
    assert pids, "No listener process was found on port 9001."
    valid = False
    for pid in pids:
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                args = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
        except FileNotFoundError:
            continue
        if (args and "python3" in os.path.basename(args[0]) and "-m" in args
                and "http.server" in args and "9001" in args
                and "--bind" in args and "127.0.0.1" in args):
            valid = True
    assert valid, "Port 9001 is not served by the required Python HTTP server."


def test_port_9002_not_running():
    """Check that port 9002 is not listening."""
    assert not is_port_in_use(9002), "Port 9002 is listening. The server should have been killed."


def test_monitor_log():
    """Check that monitor.log contains exactly the expected alert."""
    log_file = "/home/user/monitor.log"
    assert os.path.isfile(log_file), f"{log_file} does not exist."

    with open(log_file, 'r') as f:
        content = f.read()

    expected = "ALERT: PORT 9002 DOWN\n"
    assert content == expected, f"{log_file} content is incorrect. Expected {repr(expected)}, got {repr(content)}"
TEST_EOF

if python3 /tmp/verify_execution.py 2>&1 && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
