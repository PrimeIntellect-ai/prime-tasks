#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import queue
import re
import socket
import struct
import subprocess
import threading
import time

FORWARD_SCRIPT = "/home/user/port_forward.py"
MONITOR_SCRIPT = "/home/user/monitor.py"


def stop_forwarders():
    pattern = r"/home/user/port_forward[.]py"
    subprocess.run(["pkill", "-TERM", "-f", pattern], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.3)
    subprocess.run(["pkill", "-KILL", "-f", pattern], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.2)


def connect_8080(timeout=4):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        client.settimeout(3)
        try:
            client.connect(("127.0.0.1", 8080))
            return client
        except OSError as exc:
            last_error = exc
            client.close()
            time.sleep(0.05)
    raise AssertionError(f"Could not connect to port 8080: {last_error}")


def recv_exact(sock, size):
    chunks = []
    remaining = size
    while remaining:
        chunk = sock.recv(min(65536, remaining))
        assert chunk, f"Connection closed with {remaining} bytes still expected"
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def start_backend(handler):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 9090))
    server.listen(1)
    server.settimeout(5)
    errors = queue.Queue()

    def serve():
        try:
            conn, _ = server.accept()
            conn.settimeout(4)
            try:
                handler(conn)
            finally:
                conn.close()
        except BaseException as exc:
            errors.put(exc)
        finally:
            server.close()

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()

    def finish():
        thread.join(6)
        assert not thread.is_alive(), "Backend did not finish; forwarding connection was not established or closed"
        if not errors.empty():
            raise errors.get()

    return finish


def legacy_exchange():
    def handler(conn):
        data = conn.recv(1024)
        if data == b"TEST":
            conn.sendall(b"SUCCESS")

    finish = start_backend(handler)
    client = connect_8080()
    try:
        client.sendall(b"TEST")
        response = client.recv(1024)
        assert response == b"SUCCESS", "Port forwarder did not forward data correctly."
    finally:
        client.close()
        finish()


def dynamic_bidirectional_exchange():
    payload = os.urandom(180000)
    greeting = os.urandom(113)
    secret = os.urandom(67)
    expected_response = secret + hashlib.sha256(secret + payload).digest() + payload[:257][::-1]

    def handler(conn):
        # Data must be able to travel from 9090 to 8080 before the client sends anything.
        for offset in range(0, len(greeting), 11):
            conn.sendall(greeting[offset:offset + 11])
        length = struct.unpack("!I", recv_exact(conn, 4))[0]
        received = recv_exact(conn, length)
        assert received == payload, "Arbitrary client data did not reach the backend unchanged"
        for offset in range(0, len(expected_response), 13):
            conn.sendall(expected_response[offset:offset + 13])

    finish = start_backend(handler)
    client = connect_8080()
    try:
        assert recv_exact(client, len(greeting)) == greeting, "Backend-to-client forwarding failed"
        client.sendall(struct.pack("!I", len(payload)) + payload)
        response = recv_exact(client, len(expected_response))
        assert response == expected_response, "Dynamic backend response was not forwarded correctly"
    finally:
        client.close()
        finish()


def test_bashrc_timezone():
    bashrc_path = "/home/user/.bashrc"
    assert os.path.isfile(bashrc_path), f"{bashrc_path} does not exist."
    with open(bashrc_path, "r") as f:
        content = f.read()

    # Preserve the original required-text assertion.
    pattern = re.compile(r"export\s+TZ=['\"]?Asia/Tokyo['\"]?")
    assert pattern.search(content) is not None, "TZ=Asia/Tokyo export not found in .bashrc"

    # Confirm that the user's interactive shell actually receives the exported value.
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "bash", "--noprofile", "--rcfile", bashrc_path,
         "-ic", "printf '%s' \"$TZ\""],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=5, check=True
    )
    assert result.stdout == "Asia/Tokyo", ".bashrc does not actually set TZ for the user"


def test_crontab():
    try:
        output = subprocess.check_output(
            ["crontab", "-l", "-u", "user"], stderr=subprocess.STDOUT, text=True
        )
    except subprocess.CalledProcessError:
        output = ""

    # Preserve the original assertion.
    pattern = re.compile(r"\*\s+\*\s+\*\s+\*\s+\*.*python3\s+/home/user/monitor\.py")
    assert pattern.search(output) is not None, "Crontab entry for monitor.py not found or incorrect."

    # Require an active (not commented-out) every-minute entry with the instructed command.
    valid = False
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if (len(fields) >= 7 and fields[:5] == ["*", "*", "*", "*", "*"] and
                fields[5] == "/usr/bin/python3" and fields[6] == MONITOR_SCRIPT):
            valid = True
            break
    assert valid, "No active every-minute crontab entry executes the required monitor command"


def test_port_forward_script():
    assert os.path.isfile(FORWARD_SCRIPT), f"{FORWARD_SCRIPT} does not exist."
    stop_forwarders()
    pf_proc = subprocess.Popen(
        ["runuser", "-u", "user", "--", "/usr/bin/python3", FORWARD_SCRIPT],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        legacy_exchange()
        assert pf_proc.poll() is None, "port_forward.py did not continue running"
        dynamic_bidirectional_exchange()
        assert pf_proc.poll() is None, "port_forward.py stopped after handling a connection"
    finally:
        pf_proc.terminate()
        try:
            pf_proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pf_proc.kill()
            pf_proc.wait(timeout=2)
        stop_forwarders()


def test_monitor_script():
    assert os.path.isfile(MONITOR_SCRIPT), f"{MONITOR_SCRIPT} does not exist."
    stop_forwarders()

    try:
        subprocess.run(
            ["runuser", "-u", "user", "--", "/usr/bin/python3", MONITOR_SCRIPT],
            check=True, timeout=5, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        time.sleep(0.7)

        # Preserve the original process-list assertion.
        try:
            output = subprocess.check_output(["pgrep", "-f", "port_forward.py"], text=True)
            assert output.strip() != "", "monitor.py did not start port_forward.py"
        except subprocess.CalledProcessError:
            assert False, "monitor.py did not start port_forward.py"

        # The process started by monitor.py must be a functioning dynamic forwarder.
        dynamic_bidirectional_exchange()
    finally:
        stop_forwarders()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
