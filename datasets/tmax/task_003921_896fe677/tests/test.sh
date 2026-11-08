#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import socket
import stat
import subprocess
import threading
import time
import pytest

GATEWAY = "/home/user/iot_gateway"
VALID_SOCAT = None
BACKEND_SOCKET = None


def listening_inodes(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                        if local_port == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass
    return inodes


def pid_owns_socket(pid, inodes):
    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            try:
                target = os.readlink(f"/proc/{pid}/fd/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                return True
    except (FileNotFoundError, PermissionError):
        pass
    return False


def socat_processes():
    processes = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/comm", "r") as f:
                if f.read().strip() != "socat":
                    continue
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                argv = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            exe = os.readlink(f"/proc/{entry}/exe")
            if argv:
                processes.append((int(entry), argv, exe))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
    return processes


def valid_forward_args(argv):
    args = [arg.lower() for arg in argv[1:]]
    listen = any(re.match(r"^(tcp|tcp4)-listen:8443(?:,|$)", arg) for arg in args)
    destination = any(
        re.match(r"^(tcp|tcp4|tcp-connect|tcp4-connect):127\.0\.0\.1:9443(?:,|$)", arg)
        for arg in args
    )
    return listen and destination


def wait_for_listener(port, expected=True, timeout=4):
    deadline = time.time() + timeout
    while time.time() < deadline:
        present = bool(listening_inodes(port))
        if present == expected:
            return
        time.sleep(0.05)
    assert bool(listening_inodes(port)) == expected, f"Unexpected listening state for port {port}."


def stop_all_socat():
    processes = socat_processes()
    for pid, _, _ in processes:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and socat_processes():
        time.sleep(0.05)
    for pid, _, _ in socat_processes():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def start_backend():
    global BACKEND_SOCKET
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 9443))
    server.listen(16)
    BACKEND_SOCKET = server

    def serve():
        while True:
            try:
                conn, _ = server.accept()
            except OSError:
                return
            with conn:
                conn.settimeout(1)
                data = bytearray()
                try:
                    while len(data) < 4096:
                        chunk = conn.recv(4096 - len(data))
                        if not chunk:
                            break
                        data.extend(chunk)
                        if len(chunk) < 4096:
                            break
                except socket.timeout:
                    pass
                if data:
                    try:
                        conn.sendall(b"BACKEND:" + bytes(data))
                    except OSError:
                        pass

    threading.Thread(target=serve, daemon=True).start()


def run_diagnostics():
    return subprocess.run(
        [f"{GATEWAY}/diagnostics.sh"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=8,
        check=False,
    )


def exact_ok_line_count(data):
    return sum(line == b"OK_FORWARDING" for line in data.splitlines())


def test_directory_and_symlink():
    """Verify the directory structure and symlink for telemetry data."""
    dir_path = "/home/user/iot_gateway/telemetry/node_01"
    symlink_path = "/home/user/iot_gateway/current_node"

    assert os.path.isdir(dir_path), f"Directory {dir_path} does not exist."
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."

    target = os.readlink(symlink_path)
    assert target == dir_path, f"Symlink {symlink_path} points to {target}, expected {dir_path}."


def test_socat_port_forwarding():
    """Verify socat owns port 8443 and forwards it to 127.0.0.1:9443."""
    global VALID_SOCAT

    try:
        subprocess.run(["pgrep", "-x", "socat"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except subprocess.CalledProcessError:
        pytest.fail("socat process is not running.")

    try:
        result = subprocess.run(["ss", "-tln"], check=True, stdout=subprocess.PIPE, text=True)
        assert ":8443" in result.stdout, "Port 8443 is not listening."
    except subprocess.CalledProcessError:
        pytest.fail("Failed to execute ss command to check listening ports.")

    inodes = listening_inodes(8443)
    assert inodes, "Port 8443 has no TCP listening socket."

    candidates = []
    for pid, argv, exe in socat_processes():
        if valid_forward_args(argv) and pid_owns_socket(pid, inodes):
            candidates.append((pid, argv, exe))
    assert candidates, "The socat process listening on 8443 is not configured to forward to 127.0.0.1:9443."
    VALID_SOCAT = candidates[0]

    start_backend()
    challenge = os.urandom(32)
    with socket.create_connection(("127.0.0.1", 8443), timeout=3) as client:
        client.settimeout(3)
        client.sendall(challenge)
        received = bytearray()
        expected = b"BACKEND:" + challenge
        while len(received) < len(expected):
            chunk = client.recv(len(expected) - len(received))
            if not chunk:
                break
            received.extend(chunk)
    assert bytes(received) == expected, "Traffic on port 8443 was not forwarded to the test service on 127.0.0.1:9443."
    wait_for_listener(8443, expected=True)


def test_diagnostics_script():
    """Verify that the diagnostics script exists and is executable."""
    script_path = "/home/user/iot_gateway/diagnostics.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_diagnostics_behavior():
    """Execute diagnostics with port 8443 unavailable and available."""
    assert VALID_SOCAT is not None
    log_path = f"{GATEWAY}/health.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    _, argv, exe = VALID_SOCAT
    stop_all_socat()
    wait_for_listener(8443, expected=False)

    # Keep an unrelated socat process alive so merely checking pgrep cannot pass.
    dummy = subprocess.Popen(
        ["socat", "TCP-LISTEN:18443,reuseaddr,fork", "EXEC:/bin/cat"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        wait_for_listener(18443, expected=True)
        with open(log_path, "rb") as f:
            before_unreachable = f.read()
        run_diagnostics()
        with open(log_path, "rb") as f:
            after_unreachable = f.read()
        assert exact_ok_line_count(after_unreachable) == exact_ok_line_count(before_unreachable), (
            "diagnostics.sh recorded OK_FORWARDING while port 8443 was unavailable."
        )
    finally:
        dummy.terminate()
        try:
            dummy.wait(timeout=2)
        except subprocess.TimeoutExpired:
            dummy.kill()
            dummy.wait(timeout=2)

    subprocess.Popen(
        argv,
        executable=exe,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    wait_for_listener(8443, expected=True)

    with open(log_path, "rb") as f:
        before_reachable = f.read()
    run_diagnostics()
    with open(log_path, "rb") as f:
        after_reachable = f.read()

    appended = after_reachable[len(before_reachable):]
    assert appended in (b"OK_FORWARDING", b"OK_FORWARDING\n"), (
        "Running diagnostics.sh with port 8443 reachable did not append exactly OK_FORWARDING."
    )


def test_health_log_content_and_permissions():
    """Verify the health log content and its permissions."""
    log_path = "/home/user/iot_gateway/health.log"

    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read()
    assert "OK_FORWARDING" in content, f"Log file {log_path} does not contain 'OK_FORWARDING'."

    file_stat = os.stat(log_path)
    perms = stat.S_IMODE(file_stat.st_mode)
    assert perms == 0o644, f"Permissions for {log_path} are {oct(perms)}, expected 0o644."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
