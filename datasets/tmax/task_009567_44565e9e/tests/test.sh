#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import signal
import socket
import subprocess
import time

import pytest

HOME = "/home/user"
ENV_FILE = f"{HOME}/config/system.env"


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def wait_for(predicate, timeout=4.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(0.05)
    return False


def process_alive(pid):
    try:
        os.kill(pid, 0)
        with open(f"/proc/{pid}/stat") as f:
            return f.read().split()[2] != "Z"
    except (OSError, FileNotFoundError, ProcessLookupError):
        return False


def tcp_request(host, port, payload, timeout=2.0):
    with socket.create_connection((host, port), timeout=timeout) as sock:
        sock.settimeout(timeout)
        sock.sendall(payload)
        return sock.recv(4096)


def process_listen_addresses(pid, port):
    inodes = set()
    fd_dir = f"/proc/{pid}/fd"
    for name in os.listdir(fd_dir):
        try:
            target = os.readlink(os.path.join(fd_dir, name))
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            inodes.add(match.group(1))

    addresses = []
    with open("/proc/net/tcp") as f:
        next(f)
        for line in f:
            fields = line.split()
            local_hex, local_port_hex = fields[1].split(":")
            if fields[3] == "0A" and int(local_port_hex, 16) == port and fields[9] in inodes:
                addresses.append(local_hex)
    return addresses


def read_pid(path):
    with open(path) as f:
        text = f.read().strip()
    assert re.fullmatch(r"[1-9][0-9]*", text), f"Invalid PID in {path}: {text!r}"
    return int(text)


def assert_log_line(line, status):
    pattern = rf"^\[(\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}})\] STATUS: {status}\n$"
    match = re.fullmatch(pattern, line)
    assert match, f"Unexpected health log line: {line!r}"
    timestamp = datetime.datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S").timestamp()
    assert abs(time.time() - timestamp) <= 10, "Health log timestamp is not current"


def terminate(pid):
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        return
    wait_for(lambda: not process_alive(pid), timeout=2.0)
    if process_alive(pid):
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass


def test_frontend_c_fixed():
    frontend_file = "/home/user/src/frontend.c"
    assert os.path.isfile(frontend_file), f"File {frontend_file} is missing."
    with open(frontend_file, "r") as f:
        content = f.read()

    assert "192.168.99.99" not in content, "frontend.c still contains the hardcoded IP '192.168.99.99'."
    assert 'getenv("BACKEND_IP")' in content, "frontend.c does not dynamically read BACKEND_IP using getenv."
    assert 'getenv("BACKEND_PORT")' in content, "frontend.c does not dynamically read BACKEND_PORT using getenv."
    subprocess.run(["gcc", "-fsyntax-only", frontend_file], check=True, timeout=10)


def test_binaries_compiled():
    backend_bin = "/home/user/bin/backend"
    frontend_bin = "/home/user/bin/frontend"
    assert os.path.isfile(backend_bin), f"Backend binary {backend_bin} is missing."
    assert os.access(backend_bin, os.X_OK), f"Backend binary {backend_bin} is not executable."
    assert os.path.isfile(frontend_bin), f"Frontend binary {frontend_bin} is missing."
    assert os.access(frontend_bin, os.X_OK), f"Frontend binary {frontend_bin} is not executable."
    for binary in (backend_bin, frontend_bin):
        with open(binary, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"{binary} is not an ELF binary"


def test_frontend_requires_backend_environment():
    binary = "/home/user/bin/frontend"
    base = os.environ.copy()
    base["FRONTEND_PORT"] = str(free_port())

    missing_ip = base.copy()
    missing_ip.pop("BACKEND_IP", None)
    missing_ip["BACKEND_PORT"] = str(free_port())
    result = subprocess.run([binary], env=missing_ip, timeout=2)
    assert result.returncode == 1, "frontend must exit with code 1 when BACKEND_IP is unset"

    missing_port = base.copy()
    missing_port["BACKEND_IP"] = "127.0.0.2"
    missing_port.pop("BACKEND_PORT", None)
    result = subprocess.run([binary], env=missing_port, timeout=2)
    assert result.returncode == 1, "frontend must exit with code 1 when BACKEND_PORT is unset"


@pytest.fixture(scope="module")
def running_services():
    start_script = "/home/user/start_services.sh"
    assert os.path.isfile(start_script), f"Script {start_script} is missing."
    assert os.access(start_script, os.X_OK), f"Script {start_script} is not executable."

    with open(ENV_FILE) as f:
        original_env = f.read()

    backend_port = free_port()
    frontend_port = free_port()
    while frontend_port == backend_port:
        frontend_port = free_port()

    with open(ENV_FILE, "w") as f:
        f.write(f"BACKEND_IP=127.0.0.2\nBACKEND_PORT={backend_port}\nFRONTEND_PORT={frontend_port}\n")

    for name in ("backend.pid", "frontend.pid"):
        try:
            os.remove(f"{HOME}/run/{name}")
        except FileNotFoundError:
            pass
    for name in ("backend.log", "frontend.log"):
        try:
            os.remove(f"{HOME}/logs/{name}")
        except FileNotFoundError:
            pass

    backend_pid = frontend_pid = None
    try:
        subprocess.run(["bash", start_script], check=True, timeout=5)

        backend_pid_file = "/home/user/run/backend.pid"
        frontend_pid_file = "/home/user/run/frontend.pid"
        assert os.path.isfile(backend_pid_file), f"PID file {backend_pid_file} is missing."
        assert os.path.isfile(frontend_pid_file), f"PID file {frontend_pid_file} is missing."

        backend_pid = read_pid(backend_pid_file)
        frontend_pid = read_pid(frontend_pid_file)
        assert wait_for(lambda: process_alive(backend_pid)), "Backend PID is not a live process"
        assert wait_for(lambda: process_alive(frontend_pid)), "Frontend PID is not a live process"
        assert os.path.realpath(f"/proc/{backend_pid}/exe") == "/home/user/bin/backend"
        assert os.path.realpath(f"/proc/{frontend_pid}/exe") == "/home/user/bin/frontend"

        assert wait_for(lambda: bool(process_listen_addresses(frontend_pid, frontend_port))), "Frontend did not listen on FRONTEND_PORT"
        assert process_listen_addresses(frontend_pid, frontend_port) == ["0100007F"], "Frontend is not bound exclusively to 127.0.0.1"

        for pid, name in ((backend_pid, "backend"), (frontend_pid, "frontend")):
            expected = f"/home/user/logs/{name}.log"
            assert os.path.isfile(expected), f"Missing redirected log {expected}"
            assert os.path.realpath(f"/proc/{pid}/fd/1") == expected, f"{name} stdout is not redirected to its log"
            assert os.path.realpath(f"/proc/{pid}/fd/2") == expected, f"{name} stderr is not redirected to its log"

        yield {
            "backend_pid": backend_pid,
            "frontend_pid": frontend_pid,
            "backend_port": backend_port,
            "frontend_port": frontend_port,
        }
    finally:
        if backend_pid is not None:
            terminate(backend_pid)
        if frontend_pid is not None:
            terminate(frontend_pid)
        with open(ENV_FILE, "w") as f:
            f.write(original_env)


def test_start_services(running_services):
    response = tcp_request("127.0.0.1", running_services["frontend_port"], b"HEALTH_CHECK\n")
    assert b"FRONTEND: OK" in response, f"Frontend/backend health request failed: {response!r}"


def test_monitor_script(running_services):
    monitor_script = "/home/user/monitor.sh"
    assert os.path.isfile(monitor_script), f"Script {monitor_script} is missing."
    assert os.access(monitor_script, os.X_OK), f"Script {monitor_script} is not executable."

    health_log = "/home/user/logs/health.log"
    if os.path.exists(health_log):
        os.remove(health_log)

    subprocess.run(["bash", monitor_script], check=True, timeout=4)
    assert os.path.isfile(health_log), f"Log file {health_log} was not created by monitor.sh."
    with open(health_log, "r") as f:
        content = f.read()
    assert "STATUS: HEALTHY" in content, f"Expected 'STATUS: HEALTHY' in {health_log}, but got:\n{content}"
    assert_log_line(content, "HEALTHY")

    terminate(running_services["backend_pid"])
    with open(health_log, "w") as f:
        f.write("")
    subprocess.run(["bash", monitor_script], check=True, timeout=4)
    with open(health_log) as f:
        content = f.read()
    assert_log_line(content, "UNHEALTHY")


def test_monitor_enforces_timeout(running_services, tmp_path):
    terminate(running_services["frontend_pid"])
    port = running_services["frontend_port"]
    ready = tmp_path / "ready"
    server_code = r'''
import socket, sys, time
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(sys.argv[1])))
s.listen(1)
open(sys.argv[2], "w").close()
c, _ = s.accept()
c.recv(4096)
time.sleep(10)
'''
    server = subprocess.Popen(["python3", "-c", server_code, str(port), str(ready)])
    try:
        assert wait_for(ready.exists), "Dummy unresponsive TCP server did not start"
        health_log = "/home/user/logs/health.log"
        with open(health_log, "w") as f:
            f.write("")
        started = time.monotonic()
        subprocess.run(["bash", "/home/user/monitor.sh"], check=True, timeout=4)
        elapsed = time.monotonic() - started
        assert 1.5 <= elapsed <= 3.5, f"Monitor did not apply an approximately 2-second response timeout ({elapsed:.2f}s)"
        with open(health_log) as f:
            content = f.read()
        assert_log_line(content, "UNHEALTHY")
    finally:
        server.terminate()
        try:
            server.wait(timeout=2)
        except subprocess.TimeoutExpired:
            server.kill()


def test_rotate_script():
    rotate_script = "/home/user/rotate.sh"
    assert os.path.isfile(rotate_script), f"Script {rotate_script} is missing."
    assert os.access(rotate_script, os.X_OK), f"Script {rotate_script} is not executable."

    health_log = "/home/user/logs/health.log"
    rotated_log = "/home/user/logs/health.log.1"
    rotated_log_2 = "/home/user/logs/health.log.2"
    for path in (health_log, rotated_log, rotated_log_2):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    with open(health_log, "w") as f:
        f.write("one\ntwo\nthree\nfour\nfive\n")
    with open(rotated_log, "w") as f:
        f.write("older generation\n")
    subprocess.run(["bash", rotate_script], check=True)
    with open(health_log) as f:
        assert len(f.readlines()) == 5, "A five-line health.log must not rotate"
    with open(rotated_log) as f:
        assert f.read() == "older generation\n", "health.log.1 changed when rotation was not required"
    assert not os.path.exists(rotated_log_2), "health.log.2 was created when rotation was not required"

    with open(health_log, "w") as f:
        for i in range(6):
            f.write(f"Dummy line {i}\n")

    subprocess.run(["bash", rotate_script], check=True)
    assert os.path.isfile(rotated_log), f"Rotated log file {rotated_log} is missing."
    with open(rotated_log, "r") as f:
        lines = f.readlines()
    assert len(lines) == 6, f"Expected 6 lines in {rotated_log}, got {len(lines)}."

    assert os.path.isfile(health_log), f"New empty log file {health_log} is missing."
    with open(health_log, "r") as f:
        content = f.read()
    assert content == "", f"New {health_log} is not empty."
    assert os.path.isfile(rotated_log_2), "Existing health.log.1 was not moved to health.log.2"
    with open(rotated_log_2) as f:
        assert f.read() == "older generation\n"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
