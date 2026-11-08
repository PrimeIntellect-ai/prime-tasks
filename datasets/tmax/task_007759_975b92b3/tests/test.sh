#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import os
import random
import re
import secrets
import select
import shutil
import signal
import socket
import subprocess
import tempfile
import threading
import time

DAEMON = "/home/user/micro_mailer"
SOURCE = "/home/user/micro_mailer.cpp"
EXPECT_SCRIPT = "/home/user/auto_dispatch.exp"
LOG_FILE = "/home/user/digest.log"
MAILER_UNIT = "/home/user/.config/systemd/user/mailer_daemon.service"
DISPATCH_UNIT = "/home/user/.config/systemd/user/dispatch_job.service"


def stop_process(proc):
    if proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait(timeout=2)
    except (ProcessLookupError, subprocess.TimeoutExpired):
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait(timeout=2)


def read_prompt(sock):
    data = b""
    deadline = time.time() + 2
    while not data.endswith(b"\n") and time.time() < deadline:
        chunk = sock.recv(128)
        if not chunk:
            break
        data += chunk
    return data


def connect_for_prompt():
    deadline = time.time() + 4
    last_error = None
    while time.time() < deadline:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(1)
        try:
            sock.connect(("127.0.0.1", 9922))
            prompt = read_prompt(sock)
            return sock, prompt
        except OSError as exc:
            last_error = exc
            sock.close()
            time.sleep(0.05)
    raise AssertionError(f"Daemon did not accept TCP connections: {last_error}")


def assert_loopback_listener():
    listeners = []
    with open("/proc/net/tcp", "r") as f:
        for line in f.readlines()[1:]:
            fields = line.split()
            local, state = fields[1], fields[3]
            address, port = local.split(":")
            if state == "0A" and int(port, 16) == 9922:
                listeners.append(address)
    assert listeners, "No IPv4 TCP listener was found on port 9922."
    assert "0100007F" in listeners, "The daemon must listen specifically on 127.0.0.1:9922."
    assert "00000000" not in listeners, "The daemon must not bind port 9922 on all IPv4 interfaces."


def exchange(command):
    sock, prompt = connect_for_prompt()
    try:
        assert prompt == b"READY_FOR_COMMAND\n", f"Incorrect daemon prompt: {prompt!r}"
        sock.sendall(command)
        sock.shutdown(socket.SHUT_WR)
        sock.settimeout(2)
        remaining = b""
        while True:
            chunk = sock.recv(128)
            if not chunk:
                break
            remaining += chunk
        assert remaining == b"", f"Unexpected data after the prompt: {remaining!r}"
    finally:
        sock.close()


def wait_for_log_lines(expected):
    deadline = time.time() + 2
    lines = None
    while time.time() < deadline:
        if os.path.isfile(LOG_FILE):
            with open(LOG_FILE, "r") as f:
                lines = f.read().splitlines()
            if len(lines) >= len(expected):
                break
        time.sleep(0.03)
    assert lines == expected, f"Unexpected digest.log contents: {lines!r}; expected {expected!r}"


def exercise_daemon(binary):
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)
    proc = subprocess.Popen([binary], start_new_session=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        probe, prompt = connect_for_prompt()
        assert prompt == b"READY_FOR_COMMAND\n", f"Incorrect daemon prompt: {prompt!r}"
        assert_loopback_listener()
        probe.close()

        # Remove anything written merely because the process started or a client connected.
        if os.path.exists(LOG_FILE):
            os.remove(LOG_FILE)

        marker = secrets.token_hex(12).encode()
        invalid = [
            b"DISPATCH_DIGEST_" + marker + b"\n",
            b"X" + marker + b"\r\n",
            b"DISPATCH_DIGEST \n",
        ]
        random.SystemRandom().shuffle(invalid)
        for command in invalid:
            exchange(command)
        assert not os.path.exists(LOG_FILE), "Invalid commands must not create digest.log."

        valid = [b"DISPATCH_DIGEST\n", b"DISPATCH_DIGEST\r\n", b"DISPATCH_DIGEST"]
        valid += [random.SystemRandom().choice(valid) for _ in range(random.SystemRandom().randint(1, 3))]
        random.SystemRandom().shuffle(valid)
        for command in valid:
            exchange(command)
        wait_for_log_lines(["DIGEST_DISPATCHED_TO_LIST"] * len(valid))
        assert proc.poll() is None, "Daemon exited instead of continuing to listen."
    finally:
        stop_process(proc)


def parse_unit(path):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    with open(path, "r") as f:
        parser.read_file(f)
    return parser


def test_files_exist():
    """Verify all required files exist."""
    required_files = [
        SOURCE,
        DAEMON,
        EXPECT_SCRIPT,
        MAILER_UNIT,
        DISPATCH_UNIT,
    ]
    for path in required_files:
        assert os.path.isfile(path), f"Required file {path} is missing."
    assert os.access(DAEMON, os.X_OK), "/home/user/micro_mailer is not executable."
    with open(DAEMON, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/micro_mailer must be a compiled native executable."


def test_systemd_mailer_daemon():
    """Verify mailer_daemon.service configuration."""
    with open(MAILER_UNIT, "r") as f:
        content = f.read()
    assert re.search(r"Restart\s*=\s*always", content), "mailer_daemon.service must have Restart=always."
    assert "/home/user/micro_mailer" in content, "mailer_daemon.service must execute /home/user/micro_mailer."

    unit = parse_unit(MAILER_UNIT)
    assert unit.has_section("Service"), "mailer_daemon.service needs a [Service] section."
    assert unit.get("Service", "Restart", fallback="").strip().lower() == "always"
    assert unit.get("Service", "ExecStart", fallback="").strip() == DAEMON


def test_systemd_dispatch_job():
    """Verify dispatch_job.service configuration."""
    with open(DISPATCH_UNIT, "r") as f:
        content = f.read()
    assert re.search(r"Type\s*=\s*oneshot", content), "dispatch_job.service must have Type=oneshot."
    assert re.search(r"After\s*=\s*.*mailer_daemon\.service", content), "dispatch_job.service must run After mailer_daemon.service."
    assert re.search(r"(Requires|BindsTo)\s*=\s*.*mailer_daemon\.service", content), "dispatch_job.service must Require mailer_daemon.service."
    assert "/home/user/auto_dispatch.exp" in content, "dispatch_job.service must execute the expect script."

    unit = parse_unit(DISPATCH_UNIT)
    assert unit.has_section("Unit"), "dispatch_job.service needs a [Unit] section."
    assert unit.has_section("Service"), "dispatch_job.service needs a [Service] section."
    assert "mailer_daemon.service" in unit.get("Unit", "After", fallback="").split()
    strong = set(unit.get("Unit", "Requires", fallback="").split())
    strong.update(unit.get("Unit", "BindsTo", fallback="").split())
    assert "mailer_daemon.service" in strong
    assert unit.get("Service", "Type", fallback="").strip().lower() == "oneshot"
    assert unit.get("Service", "ExecStart", fallback="").strip() == "/usr/bin/expect /home/user/auto_dispatch.exp"


def test_systemd_units_are_valid():
    analyzer = shutil.which("systemd-analyze")
    assert analyzer, "systemd-analyze is unavailable."
    result = subprocess.run(
        [analyzer, "verify", MAILER_UNIT, DISPATCH_UNIT],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Invalid systemd unit configuration:\n{result.stdout}\n{result.stderr}"


def test_submitted_daemon_protocol():
    exercise_daemon(DAEMON)


def test_cpp_source_compiles_and_implements_protocol():
    output = os.path.join(tempfile.mkdtemp(prefix="mailer-build-"), "micro_mailer")
    result = subprocess.run(
        ["/usr/bin/g++", "-std=c++17", SOURCE, "-o", output],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"micro_mailer.cpp did not compile:\n{result.stdout}\n{result.stderr}"
    exercise_daemon(output)


def test_expect_waits_for_prompt_and_sends_command():
    observations = {}
    ready = threading.Event()

    def server():
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("127.0.0.1", 9922))
        listener.listen(1)
        listener.settimeout(5)
        ready.set()
        try:
            conn, _ = listener.accept()
            conn.settimeout(3)
            with conn:
                time.sleep(0.25)
                readable, _, _ = select.select([conn], [], [], 0)
                observations["sent_early"] = bool(readable)
                conn.sendall(b"READY_FOR_")
                time.sleep(0.15)
                conn.sendall(b"COMMAND\n")
                data = b""
                while b"\n" not in data and b"\r" not in data:
                    chunk = conn.recv(256)
                    if not chunk:
                        break
                    data += chunk
                observations["command"] = data
        except Exception as exc:
            observations["error"] = repr(exc)
        finally:
            listener.close()

    thread = threading.Thread(target=server, daemon=True)
    thread.start()
    assert ready.wait(2)
    result = subprocess.run(
        ["/usr/bin/expect", EXPECT_SCRIPT], capture_output=True, text=True, timeout=8
    )
    thread.join(timeout=6)
    assert not thread.is_alive(), "Expect interaction did not finish."
    assert "error" not in observations, observations.get("error")
    assert result.returncode == 0, f"Expect script failed: {result.stdout}\n{result.stderr}"
    assert observations.get("sent_early") is False, "Expect script sent data before receiving the complete prompt."
    assert observations.get("command", b"").rstrip(b"\r\n") == b"DISPATCH_DIGEST"


def test_daemon_and_expect_interaction():
    """Verify the submitted daemon and Expect script work together to write the log."""
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)
    daemon_process = subprocess.Popen([DAEMON], start_new_session=True)
    try:
        time.sleep(1.0)
        if os.path.exists(LOG_FILE):
            os.remove(LOG_FILE)
        result = subprocess.run(
            ["/usr/bin/expect", EXPECT_SCRIPT], capture_output=True, text=True, timeout=8
        )
        assert result.returncode == 0, f"Expect script failed with output: {result.stderr}"
        time.sleep(0.5)
        assert os.path.isfile(LOG_FILE), "/home/user/digest.log was not created."
        with open(LOG_FILE, "r") as f:
            log_content = f.read()
        assert "DIGEST_DISPATCHED_TO_LIST" in log_content, "Log file does not contain the expected string."
        assert log_content.splitlines() == ["DIGEST_DISPATCHED_TO_LIST"]
    finally:
        stop_process(daemon_process)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
