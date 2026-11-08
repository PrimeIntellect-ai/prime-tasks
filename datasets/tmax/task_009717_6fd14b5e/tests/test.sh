#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import signal
import socket
import stat
import subprocess
import threading
import time

import pytest

FETCH = "/home/user/fetch_stats.exp"
COLLECT = "/home/user/collect_metrics.sh"
METRICS = "/home/user/metrics.csv"


def test_01_port_forwarding():
    """Preserve the original check that 8080 reaches the legacy protocol."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2.0)
    try:
        s.connect(("127.0.0.1", 8080))
        data = s.recv(1024)
        assert b"Username: " in data, (
            "Port 8080 is open but did not return the expected legacy daemon prompt."
        )
    except ConnectionRefusedError:
        pytest.fail("Port 8080 is not listening. Port forwarding is not set up.")
    except socket.timeout:
        pytest.fail("Connection to port 8080 timed out.")
    finally:
        s.close()


def test_02_expect_script_exists():
    assert os.path.isfile(FETCH), f"Expect script {FETCH} does not exist."


def test_03_collect_metrics_script_exists_and_executable():
    assert os.path.isfile(COLLECT), f"Bash script {COLLECT} does not exist."
    assert os.access(COLLECT, os.X_OK), f"Bash script {COLLECT} is not executable."


def read_and_validate_csv(path, expected_connections, expected_bandwidth):
    assert os.path.isfile(path), f"Metrics file {path} does not exist."
    with open(path, "r") as f:
        lines = f.read().strip().splitlines()

    assert len(lines) == 1, f"Expected exactly 1 line in {path}, found {len(lines)}."
    parts = lines[0].split(",")
    assert len(parts) == 5, (
        f"Expected 5 comma-separated values, found {len(parts)} in line: {lines[0]}"
    )

    timestamp, connections, bandwidth, cpu, mem = parts
    assert timestamp.isdigit(), f"Timestamp '{timestamp}' is not a valid integer."
    assert connections == str(expected_connections), (
        f"Expected connections to be '{expected_connections}', got '{connections}'."
    )
    assert bandwidth == str(expected_bandwidth), (
        f"Expected bandwidth to be '{expected_bandwidth}', got '{bandwidth}'."
    )

    def is_numeric(value):
        try:
            float(value)
            return True
        except ValueError:
            return False

    assert is_numeric(cpu), f"CPU percent '{cpu}' is not a valid number."
    assert is_numeric(mem), f"Memory percent '{mem}' is not a valid number."
    return int(timestamp)


def test_04_original_metrics_csv_content():
    """Preserve all assertions made by the original final-state verifier."""
    read_and_validate_csv(METRICS, 404, 120)


def stop_original_legacy_daemon():
    victims = []
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\x00", b" ")
            if b"/home/user/legacy_daemon.py" in cmdline:
                victims.append(int(name))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    deadline = time.time() + 3
    while time.time() < deadline:
        if all(not os.path.exists(f"/proc/{pid}") for pid in victims):
            return
        time.sleep(0.05)

    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def recv_line(conn):
    data = bytearray()
    while len(data) < 4096:
        chunk = conn.recv(1)
        if not chunk:
            raise RuntimeError("connection closed before a complete command")
        data.extend(chunk)
        if chunk == b"\n":
            return bytes(data).strip().decode("utf-8", "replace")
    raise RuntimeError("protocol line was too long")


class RandomLegacyDaemon:
    def __init__(self, connections, bandwidth):
        self.connections = connections
        self.bandwidth = bandwidth
        self.sessions = []
        self.errors = []
        self.stop_event = threading.Event()
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

        deadline = time.time() + 4
        while True:
            try:
                self.sock.bind(("127.0.0.1", 9999))
                break
            except OSError:
                if time.time() >= deadline:
                    raise
                time.sleep(0.05)

        self.sock.listen(8)
        self.sock.settimeout(0.2)
        self.thread = threading.Thread(target=self.serve, daemon=True)

    def start(self):
        self.thread.start()

    def serve(self):
        while not self.stop_event.is_set():
            try:
                conn, _ = self.sock.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            threading.Thread(target=self.handle, args=(conn,), daemon=True).start()

    def handle(self, conn):
        conn.settimeout(4)
        transcript = []
        try:
            conn.sendall(b"Username: ")
            user = recv_line(conn)
            transcript.append(user)
            if user != "admin":
                raise AssertionError(f"wrong username: {user!r}")

            conn.sendall(b"Password: ")
            password = recv_line(conn)
            transcript.append(password)
            if password != "cap_planner":
                raise AssertionError("wrong password")

            conn.sendall(b"CMD> ")
            command = recv_line(conn)
            transcript.append(command)
            if command != "STATS":
                raise AssertionError(f"expected STATS, got {command!r}")

            response = (
                "[System Status]\n"
                f"Active Connections: {self.connections}\n"
                f"Current Bandwidth: {self.bandwidth} Mbps\n"
                "CMD> "
            ).encode()
            conn.sendall(response)

            command = recv_line(conn)
            transcript.append(command)
            if command != "QUIT":
                raise AssertionError(f"expected graceful QUIT, got {command!r}")
            conn.sendall(b"Goodbye\n")
            self.sessions.append(tuple(transcript))
        except Exception as exc:
            self.errors.append(str(exc))
        finally:
            conn.close()

    def close(self):
        self.stop_event.set()
        self.sock.close()
        self.thread.join(timeout=1)


def user_preexec():
    account = pwd.getpwnam("user")

    def demote():
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return demote


def test_05_execute_complete_pipeline_against_dynamic_service():
    """Execute both artifacts and derive the expected metrics from a fresh service."""
    with open(COLLECT, "r", errors="replace") as f:
        collector_text = f.read()
    assert FETCH in collector_text, "Collector does not invoke the required expect script."
    assert "worker_daemon.sh" in collector_text, "Collector does not identify worker_daemon.sh."
    assert METRICS in collector_text, "Collector does not write the required metrics file."

    stop_original_legacy_daemon()
    rng = random.SystemRandom()
    connections = rng.randrange(1000, 9000)
    bandwidth = rng.randrange(200, 900)
    daemon = RandomLegacyDaemon(connections, bandwidth)
    daemon.start()

    ps_path = "/usr/bin/ps"
    ps_backup = f"/usr/bin/ps.verifier-{os.getpid()}"
    ps_log = f"/tmp/ps-invocations-{os.getpid()}"
    ps_replaced = False

    try:
        # Execute the Expect source with the Expect interpreter. This validates
        # the interactive login, STATS request, raw output, and graceful QUIT.
        fetched = subprocess.run(
            ["/usr/bin/expect", FETCH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
            preexec_fn=user_preexec(),
        )
        assert fetched.returncode == 0, (
            f"fetch_stats.exp failed: stdout={fetched.stdout!r}, stderr={fetched.stderr!r}"
        )
        assert f"Active Connections: {connections}" in fetched.stdout
        assert f"Current Bandwidth: {bandwidth} Mbps" in fetched.stdout

        # Empty the previously validated one-line file, then execute the actual
        # collector once. A wrapper records that the execution really invokes ps
        # while preserving normal ps behavior and output.
        with open(METRICS, "w"):
            pass
        os.chown(METRICS, pwd.getpwnam("user").pw_uid, pwd.getpwnam("user").pw_gid)
        with open(ps_log, "w"):
            pass
        os.chmod(ps_log, 0o666)

        os.rename(ps_path, ps_backup)
        with open(ps_path, "w") as f:
            f.write("#!/bin/sh\nprintf '%s\\n' \"$*\" >> " + ps_log + "\nexec " + ps_backup + " \"$@\"\n")
        os.chmod(ps_path, 0o755)
        ps_replaced = True

        started = int(time.time())
        collected = subprocess.run(
            [COLLECT],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
            preexec_fn=user_preexec(),
        )
        finished = int(time.time())
        assert collected.returncode == 0, (
            f"collect_metrics.sh failed: stdout={collected.stdout!r}, "
            f"stderr={collected.stderr!r}"
        )

        timestamp = read_and_validate_csv(METRICS, connections, bandwidth)
        assert started - 2 <= timestamp <= finished + 2, (
            f"Collector wrote stale or fabricated timestamp {timestamp}."
        )
        with open(ps_log, "r") as f:
            ps_calls = f.read().strip()
        assert ps_calls, "collect_metrics.sh did not invoke ps while collecting worker metrics."

        deadline = time.time() + 2
        while len(daemon.sessions) < 2 and time.time() < deadline:
            time.sleep(0.05)
        assert not daemon.errors, f"Legacy protocol errors occurred: {daemon.errors}"
        assert len(daemon.sessions) == 2, (
            f"Expected one fetch session and one collector session, got {len(daemon.sessions)}."
        )
        expected_session = ("admin", "cap_planner", "STATS", "QUIT")
        assert all(session == expected_session for session in daemon.sessions)
    finally:
        if ps_replaced:
            try:
                os.unlink(ps_path)
            except FileNotFoundError:
                pass
            os.rename(ps_backup, ps_path)
        daemon.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
