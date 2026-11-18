#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shlex
import socket
import subprocess
import tempfile
import time
from pathlib import Path

BIN = "/home/user/app/bin/migrator"
LINK = "/home/user/app/active/migrator"
SOURCE = "/home/user/migrator.cpp"
PID_FILE = "/home/user/app/migrator.pid"
LOG_FILE = "/home/user/app/logs/migrator.log"


def process_socket_inodes(pid):
    result = set()
    fd_dir = f"/proc/{pid}/fd"
    try:
        names = os.listdir(fd_dir)
    except OSError:
        return result
    for name in names:
        try:
            target = os.readlink(os.path.join(fd_dir, name))
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            result.add(match.group(1))
    return result


def has_loopback_listener(pid, port):
    inodes = process_socket_inodes(pid)
    if not inodes:
        return False
    try:
        with open("/proc/net/tcp", "r") as f:
            rows = f.readlines()[1:]
    except OSError:
        return False
    for row in rows:
        fields = row.split()
        local_address, state, inode = fields[1], fields[3], fields[9]
        host_hex, port_hex = local_address.split(":")
        if (inode in inodes and state == "0A" and host_hex.upper() == "0100007F"
                and int(port_hex, 16) == port):
            return True
    return False


def wait_for(predicate, timeout=5.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.05)
    return False


def unused_port():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


def stop_process(proc):
    if proc.poll() is None:
        try:
            os.killpg(proc.pid, 15)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, 9)
            except ProcessLookupError:
                pass
            proc.wait(timeout=2)


def exercise_binary(binary, rounds=2):
    for index in range(rounds):
        port = unused_port()
        with tempfile.TemporaryDirectory(prefix="migrator-check-") as directory:
            log_path = os.path.join(directory, f"startup-{index}.log")
            env = os.environ.copy()
            env["MIGRATION_PORT"] = str(port)
            env["MIGRATION_LOG"] = log_path
            proc = subprocess.Popen(
                [binary], env=env, stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL, start_new_session=True)
            try:
                assert wait_for(lambda: proc.poll() is not None or (
                    os.path.isfile(log_path) and has_loopback_listener(proc.pid, port)
                )), f"{binary} did not listen on 127.0.0.1:{port} and create its requested log"
                assert proc.poll() is None, f"{binary} exited instead of remaining alive"
                assert has_loopback_listener(proc.pid, port), (
                    f"{binary} is not listening on 127.0.0.1:{port}")
                with open(log_path, "rb") as f:
                    assert f.read() == b"SERVICE_UP\n", (
                        f"{binary} did not write exactly SERVICE_UP followed by a newline")
                with socket.create_connection(("127.0.0.1", port), timeout=1):
                    pass
                time.sleep(0.1)
                assert proc.poll() is None, f"{binary} did not stay alive"
            finally:
                stop_process(proc)


def test_symlink_and_directories():
    assert os.path.isdir("/home/user/app/bin"), "/home/user/app/bin directory is missing."
    assert os.path.isdir("/home/user/app/active"), "/home/user/app/active directory is missing."
    assert os.path.isdir("/home/user/app/logs"), "/home/user/app/logs directory is missing."

    assert os.path.isfile(BIN), f"Compiled binary {BIN} is missing."
    assert os.access(BIN, os.X_OK), f"Compiled binary {BIN} is not executable."
    with open(BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BIN} is not a compiled ELF binary."

    assert os.path.islink(LINK), f"{LINK} is not a symlink."
    assert os.readlink(LINK) == BIN, f"Symlink {LINK} does not point to {BIN}."


def test_source_and_binary_behavior():
    assert os.path.isfile(SOURCE), f"C++ source file {SOURCE} is missing."
    rebuilt = "/tmp/migrator-rebuilt"
    result = subprocess.run(
        ["g++", SOURCE, "-o", rebuilt], stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=30)
    assert result.returncode == 0, f"{SOURCE} does not compile as C++: {result.stderr}"
    exercise_binary(rebuilt, rounds=1)
    exercise_binary(BIN, rounds=2)


def test_systemd_service():
    service_path = "/home/user/.config/systemd/user/migrator.service"
    assert os.path.isfile(service_path), f"Systemd service file {service_path} is missing."

    with open(service_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "ExecStart=/home/user/app/active/migrator" in content, "ExecStart directive is missing or incorrect."
    assert re.search(r"Environment=.*MIGRATION_PORT=9090", content), "MIGRATION_PORT environment variable not set correctly in service file."
    assert re.search(r"Environment=.*MIGRATION_LOG=/home/user/app/logs/migrator\.log", content), "MIGRATION_LOG environment variable not set correctly in service file."

    sections = {}
    current = None
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        section = re.fullmatch(r"\[([^]]+)\]", line)
        if section:
            current = section.group(1)
            sections.setdefault(current, [])
            continue
        if current is not None and "=" in line:
            key, value = line.split("=", 1)
            sections[current].append((key.strip(), value.strip()))

    service = sections.get("Service", [])
    exec_values = [value for key, value in service if key == "ExecStart"]
    assert "/home/user/app/active/migrator" in exec_values, (
        "[Service] must contain the exact ExecStart directive")

    environment = {}
    for key, value in service:
        if key != "Environment":
            continue
        try:
            tokens = shlex.split(value, comments=False, posix=True)
        except ValueError as exc:
            assert False, f"Invalid Environment directive: {exc}"
        for token in tokens:
            if "=" in token:
                name, setting = token.split("=", 1)
                environment[name] = setting
    assert environment.get("MIGRATION_PORT") == "9090"
    assert environment.get("MIGRATION_LOG") == LOG_FILE


def test_start_script():
    script_path = "/home/user/app/start.sh"
    assert os.path.isfile(script_path), f"Startup script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Startup script {script_path} is not executable."

    # Stop the previously started service only when the claimed PID really is
    # this task's binary. This permits a clean behavioral test of start.sh.
    if os.path.isfile(PID_FILE):
        try:
            old_pid_text = Path(PID_FILE).read_text().strip()
            old_pid = int(old_pid_text)
            old_exe = os.path.realpath(f"/proc/{old_pid}/exe")
            if old_exe == os.path.realpath(BIN):
                os.kill(old_pid, 15)
                wait_for(lambda: not os.path.exists(f"/proc/{old_pid}"), timeout=3)
        except (ValueError, OSError):
            pass

    Path(LOG_FILE).parent.mkdir(parents=True, exist_ok=True)
    Path(LOG_FILE).write_bytes(b"")
    try:
        os.unlink(PID_FILE)
    except FileNotFoundError:
        pass

    result = subprocess.run(
        [script_path], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, timeout=5)
    assert result.returncode == 0, "Startup script failed when executed."
    assert wait_for(lambda: os.path.isfile(PID_FILE) and Path(PID_FILE).read_text().strip().isdigit()), (
        "Startup script did not create a valid PID file")

    pid = int(Path(PID_FILE).read_text().strip())
    assert wait_for(lambda: os.path.exists(f"/proc/{pid}") and has_loopback_listener(pid, 9090)), (
        "The PID saved by start.sh is not listening on 127.0.0.1:9090")
    assert os.path.realpath(f"/proc/{pid}/exe") == os.path.realpath(BIN), (
        "The PID saved by start.sh is not the symlinked migrator binary")
    with open(f"/proc/{pid}/environ", "rb") as f:
        process_env = dict(item.split(b"=", 1) for item in f.read().split(b"\0") if b"=" in item)
    assert process_env.get(b"MIGRATION_PORT") == b"9090"
    assert process_env.get(b"MIGRATION_LOG") == LOG_FILE.encode()
    assert wait_for(lambda: os.path.isfile(LOG_FILE) and Path(LOG_FILE).read_bytes() == b"SERVICE_UP\n"), (
        "The service launched by start.sh did not append the exact startup line")


def test_service_running_and_pid():
    assert os.path.isfile(PID_FILE), f"PID file {PID_FILE} is missing."
    with open(PID_FILE, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file {PID_FILE} does not contain a valid integer."
    pid = int(pid_str)
    try:
        os.kill(pid, 0)
    except OSError:
        assert False, f"Process with PID {pid} is not running."

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.connect(("127.0.0.1", 9090))
        s.close()
    except ConnectionRefusedError:
        assert False, "No service is listening on 127.0.0.1:9090."


def test_log_output():
    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} is missing."
    with open(LOG_FILE, "r") as f:
        content = f.read()
    assert "SERVICE_UP" in content, f"Log file {LOG_FILE} does not contain 'SERVICE_UP'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
