#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import random
import re
import socket
import struct
import subprocess
import pytest

PID_FILE = "/home/user/server.pid"
LIB_FILE = "/home/user/libexpr/build/libexpr.so"
PROJECT = "/home/user/ws_eval"


def read_pid():
    assert os.path.isfile(PID_FILE), f"PID file {PID_FILE} is missing."
    with open(PID_FILE) as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file does not contain a valid integer: {pid_str}"
    return int(pid_str)


def listening_socket_inodes(port):
    wanted = f"{port:04X}"
    inodes = set()
    with open("/proc/net/tcp") as f:
        next(f)
        for line in f:
            fields = line.split()
            local = fields[1]
            state = fields[3]
            address, port_hex = local.split(":")
            if address == "0100007F" and port_hex == wanted and state == "0A":
                inodes.add(fields[9])
    return inodes


def test_server_pid_exists_and_is_the_server():
    pid = read_pid()
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} is not running.")

    exe = os.path.realpath(f"/proc/{pid}/exe")
    release_dir = os.path.realpath(f"{PROJECT}/target/release") + os.sep
    assert exe.startswith(release_dir), f"PID {pid} is not a release binary from the Rust project: {exe}"
    assert os.path.isfile(exe) and os.access(exe, os.X_OK), f"Running Rust executable is missing: {exe}"

    inodes = listening_socket_inodes(9001)
    assert inodes, "Nothing is listening on 127.0.0.1:9001"
    owned = False
    for fd in os.listdir(f"/proc/{pid}/fd"):
        try:
            target = os.readlink(f"/proc/{pid}/fd/{fd}")
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match and match.group(1) in inodes:
            owned = True
            break
    assert owned, f"PID {pid} does not own the listener on 127.0.0.1:9001"


def test_libexpr_built_and_safe():
    assert os.path.isfile(LIB_FILE), f"Shared library {LIB_FILE} was not built or is in the wrong location."

    with open("/home/user/libexpr/expr.c", errors="replace") as f:
        source = f.read()
    for call in re.findall(r"sscanf\s*\(.*?;", source, flags=re.DOTALL):
        assert not re.search(r"(?<![0-9])%s", call), "expr.c still contains an unbounded %s conversion in sscanf"

    probe = r'''
import ctypes
import random
import string
lib = ctypes.CDLL("/home/user/libexpr/build/libexpr.so")
fn = lib.evaluate_expression
fn.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_int)]
fn.restype = ctypes.c_int
rng = random.SystemRandom()
for op in ("ADD", "SUB", "MUL"):
    for _ in range(20):
        a = rng.randint(-10000, 10000)
        b = rng.randint(-10000, 10000)
        out = ctypes.c_int()
        rc = fn(f"{op} {a} {b}".encode(), ctypes.byref(out))
        expected = a + b if op == "ADD" else a - b if op == "SUB" else a * b
        assert rc == 0 and out.value == expected
bad = [
    "X" * 96 + " 1 2",
    "NOT_AN_OPERATION 1 2",
    "ADD",
    "SUB 1",
    "MUL one two",
    "",
]
for message in bad:
    assert len(message) <= 100
    out = ctypes.c_int()
    assert fn(message.encode(), ctypes.byref(out)) == -1
'''
    result = subprocess.run(["python3", "-c", probe], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert result.returncode == 0, f"libexpr failed functional/safety probing:\n{result.stderr}"


def test_rust_project_exists_and_links_libexpr():
    assert os.path.isdir(PROJECT), "Rust project directory /home/user/ws_eval is missing."
    assert os.path.isfile(f"{PROJECT}/Cargo.toml"), "Cargo.toml is missing in the Rust project."
    assert os.path.isfile(f"{PROJECT}/build.rs"), "build.rs is missing in the Rust project."

    pid = read_pid()
    exe = os.path.realpath(f"/proc/{pid}/exe")
    symbols = subprocess.run(["readelf", "-Ws", exe], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert symbols.returncode == 0, f"Could not inspect Rust executable: {symbols.stderr}"
    assert re.search(r"\bUND\b.*\bevaluate_expression\b", symbols.stdout), \
        "Rust executable is not dynamically linked to the C evaluate_expression function"

    clean_env = os.environ.copy()
    clean_env.pop("LD_LIBRARY_PATH", None)
    linked = subprocess.run(["ldd", exe], env=clean_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert linked.returncode == 0, f"ldd failed for Rust executable: {linked.stderr}"
    lib_lines = [line for line in linked.stdout.splitlines() if "libexpr.so" in line]
    assert lib_lines, "Rust executable has no dependency on libexpr.so"
    assert all("not found" not in line for line in lib_lines), \
        "libexpr.so cannot be found without manually setting LD_LIBRARY_PATH"

    mapped = []
    with open(f"/proc/{pid}/maps", errors="replace") as f:
        for line in f:
            path = line.split()[-1] if "/" in line else ""
            if path:
                mapped.append(os.path.realpath(path))
    assert os.path.realpath(LIB_FILE) in mapped, \
        "Running Rust server has not loaded /home/user/libexpr/build/libexpr.so"


def recv_exact(sock, count, initial=b""):
    data = bytearray(initial)
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        if not chunk:
            raise RuntimeError("Connection closed while receiving WebSocket data")
        data.extend(chunk)
    return bytes(data[:count]), bytes(data[count:])


def ws_send_recv(host, port, message):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    try:
        s.connect((host, port))
        key = base64.b64encode(os.urandom(16)).decode()
        handshake = (
            "GET / HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n"
        )
        s.sendall(handshake.encode())
        response = b""
        while b"\r\n\r\n" not in response:
            chunk = s.recv(4096)
            if not chunk:
                raise RuntimeError("WebSocket handshake failed")
            response += chunk
        headers, buffered = response.split(b"\r\n\r\n", 1)
        assert b"101 Switching Protocols" in headers, "WebSocket handshake failed"

        payload = message.encode()
        frame = bytearray([0x81])
        if len(payload) < 126:
            frame.append(0x80 | len(payload))
        elif len(payload) <= 0xFFFF:
            frame.append(0x80 | 126)
            frame.extend(struct.pack("!H", len(payload)))
        else:
            frame.append(0x80 | 127)
            frame.extend(struct.pack("!Q", len(payload)))
        mask = os.urandom(4)
        frame.extend(mask)
        frame.extend(byte ^ mask[i % 4] for i, byte in enumerate(payload))
        s.sendall(frame)

        head, buffered = recv_exact(s, 2, buffered)
        opcode = head[0] & 0x0F
        assert opcode == 1, f"Expected a text frame, got WebSocket opcode {opcode}"
        masked = bool(head[1] & 0x80)
        length = head[1] & 0x7F
        if length == 126:
            raw, buffered = recv_exact(s, 2, buffered)
            length = struct.unpack("!H", raw)[0]
        elif length == 127:
            raw, buffered = recv_exact(s, 8, buffered)
            length = struct.unpack("!Q", raw)[0]
        response_mask = b""
        if masked:
            response_mask, buffered = recv_exact(s, 4, buffered)
        data, _ = recv_exact(s, length, buffered)
        if masked:
            data = bytes(byte ^ response_mask[i % 4] for i, byte in enumerate(data))
        return data.decode()
    finally:
        s.close()


def test_websocket_addition():
    assert ws_send_recv("127.0.0.1", 9001, "ADD 15 25") == "40"


def test_websocket_subtraction():
    assert ws_send_recv("127.0.0.1", 9001, "SUB 100 42") == "58"


def test_websocket_buffer_overflow_safety():
    message = "THIS_IS_A_VERY_LONG_OPERATION_NAME_THAT_WOULD_CRASH_IT 10 20"
    assert ws_send_recv("127.0.0.1", 9001, message) == "ERROR"


def test_websocket_randomized_general_expressions():
    rng = random.SystemRandom()
    cases = []
    for op in ("ADD", "SUB", "MUL"):
        for _ in range(8):
            a = rng.randint(-20000, 20000)
            b = rng.randint(-20000, 20000)
            expected = a + b if op == "ADD" else a - b if op == "SUB" else a * b
            cases.append((f"{op} {a} {b}", str(expected)))
    rng.shuffle(cases)
    for message, expected in cases:
        assert ws_send_recv("127.0.0.1", 9001, message) == expected, message


def test_websocket_randomized_invalid_and_100_byte_inputs():
    rng = random.SystemRandom()
    invalid = ["X" * 96 + " 1 2", "ADD", "SUB 4", "MUL one two", ""]
    for _ in range(8):
        op = "".join(rng.choice("ABCDEFGHIJKLMNOPQRSTUVWXYZ") for _ in range(rng.randint(8, 80)))
        while op in {"ADD", "SUB", "MUL"}:
            op += "X"
        invalid.append(f"{op} {rng.randint(-99, 99)} {rng.randint(-99, 99)}")
    for message in invalid:
        assert len(message) <= 100
        assert ws_send_recv("127.0.0.1", 9001, message) == "ERROR", message

    pid = read_pid()
    os.kill(pid, 0)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
