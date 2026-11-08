#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import socket
import subprocess
import time

HOST = "127.0.0.1"
PORT = 9000
CRASH_PAYLOAD = b"SYNC -2147485000\n"


def assert_elf(path):
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable"


def connect_retry(proc=None, timeout=4.0):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        if proc is not None and proc.poll() is not None:
            raise AssertionError(f"ts_server exited early with status {proc.returncode}")
        try:
            return socket.create_connection((HOST, PORT), timeout=1.0)
        except OSError as e:
            last_error = e
            time.sleep(0.05)
    raise AssertionError(f"Failed to connect to ts_server on {HOST}:{PORT}: {last_error}")


def kill_port_listener():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9:
                        local = fields[1]
                        state = fields[3]
                        if int(local.rsplit(":", 1)[1], 16) == PORT and state == "0A":
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue

    for pid in victims:
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    time.sleep(0.25)
    for pid in victims:
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass


def command(stream, text):
    stream.write(text.encode("ascii"))
    stream.flush()
    response = stream.readline()
    assert response, f"Server closed the connection after {text!r}"
    return response.decode("ascii")


def cxx_remainder(value, divisor=86400):
    remainder = abs(value) % divisor
    return -remainder if value < 0 else remainder


def test_final_state():
    assert os.path.isfile("/home/user/reproducer.cpp"), "reproducer.cpp is missing"
    assert os.path.isfile("/home/user/reproducer"), "reproducer executable is missing"
    assert os.access("/home/user/reproducer", os.X_OK), "reproducer is not executable"
    assert_elf("/home/user/reproducer")

    assert os.path.isfile("/home/user/ts_server.cpp"), "ts_server.cpp is missing"
    assert os.path.isfile("/home/user/ts_server"), "ts_server executable is missing"
    assert os.access("/home/user/ts_server", os.X_OK), "ts_server is not executable"
    assert_elf("/home/user/ts_server")

    # Preserve the requirement that the agent left a server listening on port 9000.
    initial = connect_retry(timeout=3.0)
    initial.close()
    kill_port_listener()

    # Execute the submitted reproducer against a capture socket and verify the exact
    # newline-terminated payload recovered from the core dump.
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind((HOST, PORT))
    listener.listen(1)
    listener.settimeout(3.0)
    reproducer = subprocess.Popen(
        ["/home/user/reproducer"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    conn, _ = listener.accept()
    conn.settimeout(2.0)
    captured = bytearray()
    while b"\n" not in captured and len(captured) < 4096:
        chunk = conn.recv(4096)
        if not chunk:
            break
        captured.extend(chunk)
    conn.sendall(b"OK -13000\n")
    conn.close()
    listener.close()
    try:
        rc = reproducer.wait(timeout=3.0)
    except subprocess.TimeoutExpired:
        reproducer.kill()
        reproducer.wait()
        raise AssertionError("reproducer did not terminate after sending its payload")
    assert rc == 0, f"reproducer exited with status {rc}"
    assert bytes(captured) == CRASH_PAYLOAD, (
        f"reproducer sent {bytes(captured)!r}, expected {CRASH_PAYLOAD!r}"
    )

    # Start the submitted server executable itself, rather than trusting an unrelated
    # process that happened to be listening when verification began.
    server = subprocess.Popen(
        ["/home/user/ts_server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    sock = connect_retry(server)
    sock.settimeout(3.0)
    stream = sock.makefile("rwb", buffering=0)

    # Keep the original fixed protocol checks.
    assert command(stream, "PUT cpu_usage 1678886400 95.5\n") == "OK\n"
    assert command(stream, "PUT mem_usage 1678886400 12.1\n") == "OK\n"
    assert command(stream, "GET cpu_usage 1678886400\n") == "VAL 95.5\n"
    assert command(stream, "GET cpu_usage 1678886401\n") == "NOT_FOUND\n"
    assert command(stream, "SYNC -2147485000\n") == "OK -13000\n"

    # Exercise dynamically generated keys, timestamps, values, misses, and offsets.
    records = []
    for i in range(16):
        key = "metric_" + secrets.token_hex(8)
        timestamp = random.randint(100000000, 4000000000)
        fraction = random.choice(("25", "5", "75"))
        value = f"{random.randint(-900, 900)}.{fraction}"
        assert command(stream, f"PUT {key} {timestamp} {value}\n") == "OK\n"
        records.append((key, timestamp, value))

    random.shuffle(records)
    for key, timestamp, value in records:
        assert command(stream, f"GET {key} {timestamp}\n") == f"VAL {value}\n"
        assert command(stream, f"GET {key} {timestamp + 1}\n") == "NOT_FOUND\n"

    unknown_key = "missing_" + secrets.token_hex(10)
    assert command(stream, f"GET {unknown_key} {random.randint(1, 4000000000)}\n") == "NOT_FOUND\n"

    offsets = [-86405, -2147485000, 0, 86400, 86401]
    offsets.extend(random.randint(-4000000000, 4000000000) for _ in range(12))
    for offset in offsets:
        expected = cxx_remainder(offset)
        assert command(stream, f"SYNC {offset}\n") == f"OK {expected}\n"

    assert server.poll() is None, "ts_server did not remain running in the foreground"
    stream.close()
    sock.close()
    # Deliberately leave the verified server process running on port 9000.
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
