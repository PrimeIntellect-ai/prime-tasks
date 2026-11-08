#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import socket
import string
import subprocess
import pytest

HOST = "127.0.0.1"
PORT = 9000


def get_oracle_output(text):
    result = subprocess.run(
        ["/app/embedding_oracle", text],
        capture_output=True,
        text=True,
        check=True,
    )
    values = [float(x) for x in result.stdout.strip().split()]
    assert len(values) == 16
    return values


def pearson_correlation(x, y):
    n = len(x)
    mean_x = sum(x) / n
    mean_y = sum(y) / n
    num = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
    den_x = sum((xi - mean_x) ** 2 for xi in x)
    den_y = sum((yi - mean_y) ** 2 for yi in y)
    if den_x == 0 or den_y == 0:
        return 0.0
    return num / math.sqrt(den_x * den_y)


def send_recv(sock, msg):
    sock.sendall(msg.encode("utf-8"))
    resp = b""
    while not resp.endswith(b"\n"):
        chunk = sock.recv(1024)
        if not chunk:
            break
        resp += chunk
    return resp.decode("utf-8")


def connect():
    try:
        sock = socket.create_connection((HOST, PORT), timeout=5)
        sock.settimeout(5)
        return sock
    except Exception as exc:
        pytest.fail(f"Failed to connect to {HOST}:{PORT}. Error: {exc}")


def assert_exit_closes(sock):
    resp = send_recv(sock, "EXIT\n")
    assert resp == "GOODBYE\n", f"Expected GOODBYE\\n, got {resp!r}"
    sock.settimeout(1)
    try:
        chunk = sock.recv(1024)
        assert chunk == b"", "Connection should be closed after EXIT"
    except socket.timeout:
        pytest.fail("Connection was not closed after EXIT command")
    except socket.error:
        pass


def listening_socket_inodes():
    wanted = f"{PORT:04X}"
    inodes = set()
    with open("/proc/net/tcp", "r", encoding="ascii") as handle:
        next(handle)
        for line in handle:
            fields = line.split()
            local_address = fields[1]
            state = fields[3]
            address, port = local_address.split(":")
            if address == "0100007F" and port.upper() == wanted and state == "0A":
                inodes.add(fields[9])
    return inodes


def test_running_artifact_is_required_elf_binary():
    path = "/home/user/server"
    assert os.path.isfile(path), f"Missing required binary {path}"
    assert os.access(path, os.X_OK), f"{path} is not executable"
    with open(path, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", f"{path} is not an ELF executable"

    inodes = listening_socket_inodes()
    assert inodes, "No IPv4 listener found on 127.0.0.1:9000"
    owners = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        owns_listener = False
        for fd in fds:
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                owns_listener = True
                break
        if owns_listener:
            owners.append(pid)

    assert owners, "Could not find the process owning the listening socket"
    running_required_binary = False
    for pid in owners:
        try:
            if os.path.samefile(f"/proc/{pid}/exe", path):
                running_required_binary = True
                break
        except OSError:
            continue
    assert running_required_binary, "The listener is not /home/user/server"


def random_valid_text(length, used):
    alphabet = string.ascii_letters + string.digits
    while True:
        text = "".join(secrets.choice(alphabet) for _ in range(length))
        if text not in used:
            used.add(text)
            return text


def test_tcp_server_protocol_and_general_behavior():
    used = {"abcdefgh", "12345678"}
    vectors = {}

    # Preserve the original fixed protocol assertions.
    s = connect()
    with s:
        resp = send_recv(s, "EMBED abc\n")
        assert resp == "ERROR_SCHEMA\n", f"Expected ERROR_SCHEMA\\n, got {resp!r}"

        resp = send_recv(s, "EMBED abcdefgh!@\n")
        assert resp == "ERROR_SCHEMA\n", f"Expected ERROR_SCHEMA\\n, got {resp!r}"

        resp = send_recv(s, "EMBED abcdefgh\n")
        assert resp == "OK 0\n", f"Expected OK 0\\n, got {resp!r}"

        resp = send_recv(s, "EMBED 12345678\n")
        assert resp == "OK 1\n", f"Expected OK 1\\n, got {resp!r}"

        vectors[0] = get_oracle_output("abcdefgh")
        vectors[1] = get_oracle_output("12345678")
        expected_corr = pearson_correlation(vectors[0], vectors[1])
        expected_resp = f"{expected_corr:.4f}\n"
        resp = send_recv(s, "CORRELATE 0 1\n")
        assert resp == expected_resp, f"Expected {expected_resp!r}, got {resp!r}"

        resp = send_recv(s, "CORRELATE 0 99\n")
        assert resp == "ERROR_NOT_FOUND\n", f"Expected ERROR_NOT_FOUND\\n, got {resp!r}"

        assert_exit_closes(s)

    # Use unpredictable texts of varied and boundary lengths on a new connection.
    lengths = [8, 9, 12, 15, 16, secrets.choice(range(8, 17))]
    random_texts = [random_valid_text(length, used) for length in lengths]

    s = connect()
    with s:
        too_long = random_valid_text(17, used)
        resp = send_recv(s, f"EMBED {too_long}\n")
        assert resp == "ERROR_SCHEMA\n"

        resp = send_recv(s, "EMBED Ab12_cd34\n")
        assert resp == "ERROR_SCHEMA\n"

        unknown = "CMD" + secrets.token_hex(6)
        resp = send_recv(s, f"{unknown}\n")
        assert resp == "ERROR_INVALID\n"

        for offset, text in enumerate(random_texts):
            index = 2 + offset
            resp = send_recv(s, f"EMBED {text}\n")
            assert resp == f"OK {index}\n", (
                f"Expected OK {index} for unpredictable valid text {text!r}, got {resp!r}"
            )
            vectors[index] = get_oracle_output(text)

        # Exercise stored vectors in many combinations, including data from the
        # previous connection and correlations in both index orders.
        indices = sorted(vectors)
        pairs = [(0, indices[-1]), (indices[-1], 1), (indices[2], indices[2])]
        for i in range(2, len(indices)):
            for j in range(i + 1, len(indices)):
                pairs.append((indices[i], indices[j]))
        secrets.SystemRandom().shuffle(pairs)

        for left, right in pairs:
            expected = pearson_correlation(vectors[left], vectors[right])
            expected_resp = f"{expected:.4f}\n"
            resp = send_recv(s, f"CORRELATE {left} {right}\n")
            assert resp == expected_resp, (
                f"Expected {expected_resp!r} for CORRELATE {left} {right}, got {resp!r}"
            )

        resp = send_recv(s, "CORRELATE -1 0\n")
        assert resp == "ERROR_NOT_FOUND\n"
        resp = send_recv(s, f"CORRELATE 0 {len(vectors) + 1000}\n")
        assert resp == "ERROR_NOT_FOUND\n"
        assert_exit_closes(s)

    # A third sequential connection must still accept commands and retain state.
    final_text = random_valid_text(secrets.choice(range(8, 17)), used)
    final_index = len(vectors)
    s = connect()
    with s:
        resp = send_recv(s, f"EMBED {final_text}\n")
        assert resp == f"OK {final_index}\n"
        vectors[final_index] = get_oracle_output(final_text)

        previous = secrets.choice(list(range(final_index)))
        expected = pearson_correlation(vectors[previous], vectors[final_index])
        expected_resp = f"{expected:.4f}\n"
        resp = send_recv(s, f"CORRELATE {previous} {final_index}\n")
        assert resp == expected_resp

        resp = send_recv(s, f"CORRELATE {final_index} {previous}\n")
        assert resp == expected_resp
        assert_exit_closes(s)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
