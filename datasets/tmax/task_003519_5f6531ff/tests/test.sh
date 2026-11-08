#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import socket
import time
import pytest

HOST = '127.0.0.1'
PORT = 8888
TOKEN = "TKN-88X9-A"
C_FILE = "/home/user/new_diagd.c"
BIN_FILE = "/home/user/new_diagd"


def test_files_exist():
    assert os.path.isfile(C_FILE), f"Expected C source file {C_FILE} to exist."
    assert os.path.isfile(BIN_FILE), f"Expected compiled binary {BIN_FILE} to exist."
    assert os.access(BIN_FILE, os.X_OK), f"Expected {BIN_FILE} to be executable."
    with open(BIN_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Expected {BIN_FILE} to be a compiled ELF executable."


def listening_socket_inodes():
    wanted = f"0100007F:{PORT:04X}"
    inodes = set()
    with open('/proc/net/tcp', 'r') as f:
        next(f)
        for line in f:
            fields = line.split()
            if fields[1].upper() == wanted and fields[3] == '0A':
                inodes.add(fields[9])
    return inodes


def test_listener_is_submitted_executable():
    inodes = listening_socket_inodes()
    assert inodes, f"No IPv4 listener found on {HOST}:{PORT}."

    owners = []
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        fd_dir = f'/proc/{name}/fd'
        try:
            fds = os.listdir(fd_dir)
        except (FileNotFoundError, PermissionError):
            continue
        for fd in fds:
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except (FileNotFoundError, PermissionError, OSError):
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                owners.append(int(name))
                break

    assert owners, "Could not identify the process owning the listening socket."
    for pid in owners:
        exe = f'/proc/{pid}/exe'
        try:
            assert os.path.samefile(exe, BIN_FILE), \
                f"Listener PID {pid} is not running {BIN_FILE}."
        except FileNotFoundError:
            pytest.fail(f"Listener PID {pid} exited while being inspected.")


def send_and_receive(sock, message, buffer_size=1024):
    sock.sendall(message.encode('utf-8'))
    response = sock.recv(buffer_size).decode('utf-8')
    return response


def recv_line(sock):
    data = bytearray()
    while not data.endswith(b'\n'):
        chunk = sock.recv(4096)
        assert chunk, f"Connection closed before a complete response; received {bytes(data)!r}"
        data.extend(chunk)
        assert len(data) <= 8192, "Response was unexpectedly large."
    return data.decode('utf-8')


def connect():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2.0)
    try:
        s.connect((HOST, PORT))
    except Exception:
        s.close()
        raise
    return s


def authenticate(sock, fragmented=False):
    request = f"AUTH {TOKEN}\n".encode()
    if fragmented:
        cuts = (2, 7, len(request) - 1)
        start = 0
        for end in cuts:
            sock.sendall(request[start:end])
            start = end
            time.sleep(0.01)
        sock.sendall(request[start:])
    else:
        sock.sendall(request)
    assert recv_line(sock) == "AUTH_OK\n"


def test_valid_auth():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(2.0)
        try:
            s.connect((HOST, PORT))
        except ConnectionRefusedError:
            pytest.fail(f"Could not connect to {HOST}:{PORT}. Is the daemon running?")

        response = send_and_receive(s, f"AUTH {TOKEN}\n")
        assert response == "AUTH_OK\n", f"Expected 'AUTH_OK\\n', got {repr(response)}"


def test_invalid_auth():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(2.0)
        try:
            s.connect((HOST, PORT))
        except ConnectionRefusedError:
            pytest.fail(f"Could not connect to {HOST}:{PORT}. Is the daemon running?")

        response = send_and_receive(s, "AUTH INVALID\n")
        assert response == "AUTH_FAIL\n", f"Expected 'AUTH_FAIL\\n', got {repr(response)}"

        try:
            extra = s.recv(1024)
            assert not extra, "Expected connection to be closed after invalid auth."
        except (socket.timeout, ConnectionResetError):
            pass


def test_valid_cmd():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(2.0)
        try:
            s.connect((HOST, PORT))
        except ConnectionRefusedError:
            pytest.fail(f"Could not connect to {HOST}:{PORT}. Is the daemon running?")

        auth_resp = send_and_receive(s, f"AUTH {TOKEN}\n")
        assert auth_resp == "AUTH_OK\n", f"Auth failed, got {repr(auth_resp)}"

        cmd_resp = send_and_receive(s, "CMD 0005 hello\n")
        assert cmd_resp == "CMD_RECV 5\n", f"Expected 'CMD_RECV 5\\n', got {repr(cmd_resp)}"


def test_large_cmd():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(2.0)
        try:
            s.connect((HOST, PORT))
        except ConnectionRefusedError:
            pytest.fail(f"Could not connect to {HOST}:{PORT}. Is the daemon running?")

        auth_resp = send_and_receive(s, f"AUTH {TOKEN}\n")
        assert auth_resp == "AUTH_OK\n", f"Auth failed, got {repr(auth_resp)}"

        cmd_resp = send_and_receive(s, "CMD FFFF exploitpayload\n")
        assert cmd_resp == "ERR_TOO_LARGE\n", f"Expected 'ERR_TOO_LARGE\\n', got {repr(cmd_resp)}"


def test_random_lengths_boundary_payloads_and_command_series():
    lengths = [0, 1, 2, 15, 16, 255, 256, 1023, 1024]
    lengths.extend(secrets.randbelow(1016) + 7 for _ in range(6))
    # Runtime ordering and values prevent a fixed transcript responder.
    for i in range(len(lengths) - 1, 0, -1):
        j = secrets.randbelow(i + 1)
        lengths[i], lengths[j] = lengths[j], lengths[i]

    with connect() as s:
        authenticate(s, fragmented=True)
        for index, length in enumerate(lengths):
            alphabet = b'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-'
            payload = bytes(alphabet[secrets.randbelow(len(alphabet))] for _ in range(length))
            hex_length = f"{length:04x}" if index % 2 else f"{length:04X}"
            packet = b"CMD " + hex_length.encode() + b" " + payload + b"\n"

            # Deliberately split both the header and payload across TCP writes.
            cuts = sorted(set([1, min(6, len(packet)), min(9, len(packet)), len(packet)]))
            start = 0
            for end in cuts:
                if end > start:
                    s.sendall(packet[start:end])
                    start = end
                    time.sleep(0.002)
            assert recv_line(s) == f"CMD_RECV {length}\n"


def test_runtime_generated_oversized_lengths_are_rejected_and_ignored():
    large_lengths = [1025, 1026 + secrets.randbelow(64509), 65535]
    with connect() as s:
        authenticate(s)
        for length in large_lengths:
            payload_length = 20 + secrets.randbelow(80)
            payload = secrets.token_hex((payload_length + 1) // 2)[:payload_length]
            request = f"CMD {length:04X} {payload}\n"
            s.sendall(request.encode())
            assert recv_line(s) == "ERR_TOO_LARGE\n"

            # The rejected line must not corrupt parsing of the next command.
            follow_length = 3 + secrets.randbelow(60)
            follow_payload = 'q' * follow_length
            s.sendall(f"CMD {follow_length:04X} {follow_payload}\n".encode())
            assert recv_line(s) == f"CMD_RECV {follow_length}\n"


def test_invalid_auth_really_closes_connection():
    wrong = "WRONG-" + secrets.token_hex(12)
    with connect() as s:
        s.sendall(f"AUTH {wrong}\n".encode())
        assert recv_line(s) == "AUTH_FAIL\n"
        s.settimeout(1.0)
        try:
            remaining = s.recv(1)
        except ConnectionResetError:
            remaining = b''
        except socket.timeout:
            pytest.fail("Connection remained open after invalid authentication.")
        assert remaining == b'', "Connection remained open after invalid authentication."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
