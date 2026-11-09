#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import signal
import socket
import subprocess
import threading
import time
import pytest

WATCHDOG = "/home/user/watchdog.py"
PROXY = "/home/user/net_route.py"
EXPORTER = "/home/user/metric_exporter.py"
DAEMON = "/home/user/mock_email_daemon.py"


def wait_until(predicate, timeout=6, interval=0.05, message="condition not met"):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            value = predicate()
            if value:
                return value
        except (OSError, ValueError):
            pass
        time.sleep(interval)
    pytest.fail(message)


def process_args(pid):
    try:
        raw = open(f"/proc/{pid}/cmdline", "rb").read()
        return [part.decode(errors="replace") for part in raw.split(b"\0") if part]
    except OSError:
        return []


def child_daemon_pids(parent_pid):
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            status = open(f"/proc/{name}/status").read().splitlines()
            ppid = int(next(line.split()[1] for line in status if line.startswith("PPid:")))
        except (OSError, StopIteration, ValueError):
            continue
        if ppid == parent_pid and DAEMON in process_args(int(name)):
            found.append(int(name))
    return found


def kill_submission_processes():
    targets = {WATCHDOG, PROXY, EXPORTER, DAEMON}
    me = os.getpid()
    victims = []
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == me:
            continue
        pid = int(name)
        args = process_args(pid)
        if any(target in args for target in targets):
            victims.append(pid)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.2)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def stop_process(proc):
    if proc is None:
        return
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)


def connect_retry(port, timeout=5):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            return socket.create_connection(("127.0.0.1", port), timeout=1)
        except OSError as exc:
            last = exc
            time.sleep(0.05)
    raise AssertionError(f"port {port} did not become available: {last}")


def recv_line(sock, timeout=2):
    sock.settimeout(timeout)
    data = bytearray()
    while not data.endswith(b"\n"):
        chunk = sock.recv(1)
        if not chunk:
            break
        data.extend(chunk)
        if len(data) > 4096:
            raise AssertionError("protocol line was too long")
    return bytes(data)


def log_lines(path):
    try:
        with open(path) as f:
            return [line.rstrip("\n") for line in f]
    except FileNotFoundError:
        return []


def test_files_exist():
    required_files = [WATCHDOG, PROXY, EXPORTER]
    for filepath in required_files:
        assert os.path.exists(filepath), f"Missing required file: {filepath}"
        assert os.path.isfile(filepath), f"Path is not a file: {filepath}"


def test_system_integration():
    """Run the real stack, prove child supervision, then crash and restart it."""
    kill_submission_processes()
    for path in ("/home/user/watchdog.log", "/home/user/observability.log"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    watchdog_proc = net_route_proc = metric_exporter_proc = None
    try:
        watchdog_proc = subprocess.Popen(
            ["python3", WATCHDOG], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        old_pid = wait_until(
            lambda: child_daemon_pids(watchdog_proc.pid)[0] if child_daemon_pids(watchdog_proc.pid) else None,
            message="watchdog did not launch mock_email_daemon.py as its child",
        )
        assert watchdog_proc.poll() is None

        # The launched child must really be the supplied authenticated SMTP daemon.
        with connect_retry(8025) as direct:
            direct.sendall(b"AUTH_TOKEN: obs_admin\n")
            assert recv_line(direct).startswith(b"220 "), "launched daemon did not provide its SMTP banner"
            direct.sendall(b"EHLO direct-check\r\n")
            assert recv_line(direct).startswith(b"250 ")
            direct.sendall(b"QUIT\r\n")

        net_route_proc = subprocess.Popen(
            ["python3", PROXY], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        with connect_retry(9025) as routed:
            # A banner through the proxy proves that the required token reached the real daemon.
            assert recv_line(routed).startswith(b"220 "), "proxy did not authenticate to the daemon"
            routed.sendall(b"EHLO routed-check\r\n")
            assert recv_line(routed).startswith(b"250 "), "client-to-daemon forwarding failed"
            routed.sendall(b"UNKNOWN-" + secrets.token_hex(8).encode() + b"\r\n")
            assert recv_line(routed).startswith(b"500 "), "daemon-to-client forwarding failed"
            routed.sendall(b"QUIT\r\n")

        metric_exporter_proc = subprocess.Popen(
            ["python3", EXPORTER], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        wait_until(
            lambda: log_lines("/home/user/observability.log").count("email_service_up 1") >= 3,
            timeout=6,
            message="exporter did not produce three successful observations",
        )

        before = log_lines("/home/user/watchdog.log").count("[SUPERVISOR] daemon restarted")
        with socket.create_connection(("127.0.0.1", 9025), timeout=2) as routed:
            assert recv_line(routed).startswith(b"220 ")
            routed.sendall(b"CRASH\r\n")

        new_pid = wait_until(
            lambda: next((pid for pid in child_daemon_pids(watchdog_proc.pid) if pid != old_pid), None),
            timeout=5,
            message="watchdog did not replace the crashed daemon child",
        )
        assert new_pid != old_pid
        wait_until(
            lambda: log_lines("/home/user/watchdog.log").count("[SUPERVISOR] daemon restarted") > before,
            message="watchdog did not log the real restart",
        )

        # Confirm that the replacement process actually serves through the proxy.
        with connect_retry(9025) as routed:
            assert recv_line(routed).startswith(b"220 ")
            routed.sendall(b"EHLO after-restart\r\n")
            assert recv_line(routed).startswith(b"250 ")
            routed.sendall(b"QUIT\r\n")

        watchdog_log_path = "/home/user/watchdog.log"
        assert os.path.exists(watchdog_log_path), "watchdog.log was not created."
        with open(watchdog_log_path) as f:
            watchdog_content = f.read()
        assert "[SUPERVISOR] daemon restarted" in watchdog_content, \
            "watchdog.log does not contain the expected restart message."

        observability_log_path = "/home/user/observability.log"
        assert os.path.exists(observability_log_path), "observability.log was not created."
        with open(observability_log_path) as f:
            observability_content = f.read()
        up_count = observability_content.count("email_service_up 1")
        assert up_count >= 3, \
            f"Expected at least 3 'email_service_up 1' in observability.log, found {up_count}."
    finally:
        stop_process(metric_exporter_proc)
        stop_process(net_route_proc)
        stop_process(watchdog_proc)
        kill_submission_processes()


def test_proxy_injects_token_and_forwards_random_data_both_ways():
    """Use a recording backend so a fabricated SMTP service cannot pass."""
    kill_submission_processes()
    ready = threading.Event()
    errors = []
    seen = {}
    payload = ("CLIENT-" + secrets.token_hex(20) + "\r\n").encode()
    banner = ("220 BANNER-" + secrets.token_hex(16) + "\r\n").encode()
    reply = ("251 REPLY-" + secrets.token_hex(16) + "\r\n").encode()

    def backend():
        try:
            with socket.socket() as server:
                server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                server.bind(("127.0.0.1", 8025))
                server.listen(1)
                server.settimeout(5)
                ready.set()
                conn, _ = server.accept()
                with conn:
                    conn.settimeout(3)
                    data = bytearray()
                    while b"\n" not in data:
                        data.extend(conn.recv(1024))
                    first, remainder = bytes(data).split(b"\n", 1)
                    seen["token"] = first + b"\n"
                    conn.sendall(banner)
                    data = bytearray(remainder)
                    while len(data) < len(payload):
                        chunk = conn.recv(1024)
                        if not chunk:
                            break
                        data.extend(chunk)
                    seen["payload"] = bytes(data[:len(payload)])
                    conn.sendall(reply)
        except BaseException as exc:
            errors.append(exc)
            ready.set()

    thread = threading.Thread(target=backend, daemon=True)
    thread.start()
    assert ready.wait(2)
    proxy_proc = subprocess.Popen(
        ["python3", PROXY], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        with connect_retry(9025) as client:
            # Send immediately; the backend must still see the injected token first.
            client.sendall(payload)
            assert recv_line(client) == banner
            assert recv_line(client) == reply
        thread.join(4)
        assert not thread.is_alive(), "recording backend did not complete"
        assert not errors, f"recording backend failed: {errors}"
        assert seen.get("token") == b"AUTH_TOKEN: obs_admin\n"
        assert seen.get("payload") == payload
    finally:
        stop_process(proxy_proc)
        kill_submission_processes()


def test_exporter_polls_ehlo_and_reports_derived_success_and_failure():
    """Random backend outcomes must produce matching metrics from real EHLO polls."""
    kill_submission_processes()
    path = "/home/user/observability.log"
    try:
        os.remove(path)
    except FileNotFoundError:
        pass

    outcomes = [True, False, bool(secrets.randbits(1)), bool(secrets.randbits(1)), bool(secrets.randbits(1))]
    # Randomize positions while retaining at least one success and one failure.
    for i in range(len(outcomes) - 1, 0, -1):
        j = secrets.randbelow(i + 1)
        outcomes[i], outcomes[j] = outcomes[j], outcomes[i]

    ready = threading.Event()
    errors = []
    commands = []
    quit_commands = []
    accept_times = []

    def fake_proxy():
        try:
            with socket.socket() as server:
                server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                server.bind(("127.0.0.1", 9025))
                server.listen(5)
                server.settimeout(3)
                ready.set()
                for index, success in enumerate(outcomes):
                    conn, _ = server.accept()
                    accept_times.append(time.monotonic())
                    with conn:
                        conn.settimeout(2)
                        conn.sendall(("220 CHECK-" + secrets.token_hex(10) + "\r\n").encode())
                        commands.append(recv_line(conn))
                        if success:
                            conn.sendall(("250 OK-" + secrets.token_hex(10) + "\r\n").encode())
                            quit_commands.append(recv_line(conn))
                            conn.sendall(b"221 Bye\r\n")
                        else:
                            conn.sendall(("550 FAIL-" + secrets.token_hex(10) + "\r\n").encode())
        except BaseException as exc:
            errors.append(exc)
            ready.set()

    thread = threading.Thread(target=fake_proxy, daemon=True)
    thread.start()
    assert ready.wait(2)
    exporter_proc = subprocess.Popen(
        ["python3", EXPORTER], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        thread.join(9)
        assert not thread.is_alive(), "exporter did not perform the required periodic polls"
        assert not errors, f"fake proxy failed: {errors}"
        stop_process(exporter_proc)

        expected = [f"email_service_up {1 if value else 0}" for value in outcomes]
        lines = wait_until(
            lambda: log_lines(path) if len(log_lines(path)) >= len(expected) else None,
            timeout=2,
            message="exporter did not write one metric per poll",
        )
        assert lines == expected, f"metrics did not match randomized SMTP outcomes: {lines}"
        assert commands == [b"EHLO monitor\r\n"] * len(outcomes), \
            f"exporter did not send the required EHLO command: {commands}"
        assert quit_commands == [b"QUIT\r\n"] * sum(outcomes), \
            f"exporter did not send QUIT after successful EHLO: {quit_commands}"
        assert len(accept_times) == len(outcomes)
        intervals = [b - a for a, b in zip(accept_times, accept_times[1:])]
        assert all(0.7 <= value <= 1.8 for value in intervals), \
            f"exporter was not polling approximately once per second: {intervals}"
    finally:
        stop_process(exporter_proc)
        kill_submission_processes()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
