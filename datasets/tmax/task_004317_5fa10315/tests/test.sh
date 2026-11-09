#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import signal
import socket
import stat
import struct
import subprocess
import time
import pytest

HOST = "127.0.0.1"
PORT = 8080
KEY = 42
EMULATOR = "/home/user/c2_emulator"


def listener_records():
    records = []
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_address = fields[1]
                    state = fields[3]
                    if state != "0A":
                        continue
                    address, port_hex = local_address.rsplit(":", 1)
                    if int(port_hex, 16) == PORT:
                        records.append((path, address, fields[9]))
        except FileNotFoundError:
            pass
    return records


def pids_owning(inodes):
    owners = set()
    wanted = {f"socket:[{inode}]" for inode in inodes}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(f"{fd_dir}/{fd}") in wanted:
                        owners.add(int(entry))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return owners


def stop_existing_listener():
    records = listener_records()
    owners = pids_owning([record[2] for record in records])
    for pid in owners:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_records():
        time.sleep(0.05)
    if listener_records():
        owners = pids_owning([record[2] for record in listener_records()])
        for pid in owners:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        time.sleep(0.1)


def recv_exact(sock, length):
    data = bytearray()
    while len(data) < length:
        chunk = sock.recv(length - len(data))
        assert chunk, f"Connection closed after {len(data)} of {length} expected bytes"
        data.extend(chunk)
    return bytes(data)


def encoded_frame(plaintext):
    payload = bytes(byte ^ KEY for byte in plaintext)
    return struct.pack(">I", len(payload)) + payload


@pytest.fixture(scope="module")
def emulator():
    assert os.path.exists(EMULATOR), f"Missing required executable: {EMULATOR}"
    mode = os.stat(EMULATOR).st_mode
    assert stat.S_ISREG(mode), f"{EMULATOR} is not a regular file"
    assert os.access(EMULATOR, os.X_OK), f"{EMULATOR} is not executable"
    with open(EMULATOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EMULATOR} is not a compiled ELF executable"

    stop_existing_listener()
    proc = subprocess.Popen(
        [EMULATOR],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    deadline = time.time() + 5
    records = []
    while time.time() < deadline:
        assert proc.poll() is None, "c2_emulator exited before opening its listening socket"
        records = listener_records()
        if records:
            owned = pids_owning([record[2] for record in records])
            if proc.pid in owned:
                break
        time.sleep(0.05)
    else:
        proc.terminate()
        pytest.fail("c2_emulator did not listen on TCP port 8080")

    owned_records = [record for record in records if proc.pid in pids_owning([record[2]])]
    assert any(path == "/proc/net/tcp" and address == "00000000"
               for path, address, _ in owned_records), \
        "c2_emulator must bind its IPv4 listener to 0.0.0.0:8080"

    yield proc

    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)


def assert_no_response(frame):
    with socket.create_connection((HOST, PORT), timeout=2) as sock:
        sock.settimeout(0.5)
        sock.sendall(frame)
        sock.shutdown(socket.SHUT_WR)
        try:
            data = sock.recv(64)
        except (socket.timeout, ConnectionResetError):
            return
        assert data == b"", f"Server responded to a non-handshake frame: {data.hex()}"


def perform_valid_handshake(fragmented):
    request = encoded_frame(b"HELLO C2")
    expected_payload = bytes(byte ^ KEY for byte in b"WELCOME")

    with socket.create_connection((HOST, PORT), timeout=2) as sock:
        sock.settimeout(2)
        if fragmented:
            position = 0
            while position < len(request):
                step = random.randint(1, min(3, len(request) - position))
                sock.sendall(request[position:position + step])
                position += step
                time.sleep(0.015)
        else:
            sock.sendall(request)

        length_data = recv_exact(sock, 4)
        response_length = struct.unpack(">I", length_data)[0]
        assert response_length == len(expected_payload), \
            f"Expected response length {len(expected_payload)}, got {response_length}"
        response_payload = recv_exact(sock, response_length)
        assert response_payload == expected_payload, \
            f"Expected payload {expected_payload.hex()}, got {response_payload.hex()}"


def test_c2_emulator_protocol_and_continuity(emulator):
    # Randomized encrypted near-misses must not receive the hardcoded WELCOME frame.
    for _ in range(4):
        invalid = bytearray(b"HELLO C2")
        index = random.randrange(len(invalid))
        invalid[index] ^= random.randrange(1, 256)
        assert_no_response(encoded_frame(bytes(invalid)))

    # An unencrypted copy is also not a valid handshake under XOR key 42.
    assert_no_response(struct.pack(">I", 8) + b"HELLO C2")

    # Preserve the original exact response assertion, while exercising framing
    # across fragmented reads and multiple sequential connections.
    for attempt in range(6):
        perform_valid_handshake(fragmented=(attempt != 0))
        assert emulator.poll() is None, "c2_emulator stopped serving connections"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
