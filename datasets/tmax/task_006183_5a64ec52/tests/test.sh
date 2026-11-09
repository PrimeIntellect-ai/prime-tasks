#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import ctypes
import json
import os
import secrets
import shutil
import socket
import string
import struct
import subprocess
import time

import pytest

PROJECT = "/home/user/project"
SOURCE = f"{PROJECT}/src/sanitizer.c"
LIBRARY = f"{PROJECT}/build/libsanitizer.so"
PID_FILE = f"{PROJECT}/server.pid"
INVOKE_LOG = f"/tmp/sanitizer-invocations-{secrets.token_hex(16)}.log"
ORIGINAL_SOURCE = None


def instrumented_source():
    log_path = json.dumps(INVOKE_LOG)
    return f'''#include <stdio.h>
#include <string.h>

int is_safe_payload(const char* payload) {{
    FILE *log = fopen({log_path}, "a");
    if (log != NULL) {{
        fprintf(log, "%s\\n", payload);
        fclose(log);
    }}
    if (strstr(payload, "<script>") != NULL) return 0;
    if (strstr(payload, "DROP TABLE") != NULL) return 0;
    if (strstr(payload, "OR 1=1") != NULL) return 0;
    return 1;
}}
'''


def cleanup():
    if os.path.exists(PID_FILE):
        with open(PID_FILE, "r") as f:
            pid_str = f.read().strip()
        if pid_str.isdigit():
            try:
                os.kill(int(pid_str), 9)
            except ProcessLookupError:
                pass

    if ORIGINAL_SOURCE is not None:
        with open(SOURCE, "wb") as f:
            f.write(ORIGINAL_SOURCE)

    try:
        os.remove(INVOKE_LOG)
    except FileNotFoundError:
        pass


@pytest.fixture(scope="module", autouse=True)
def setup_and_teardown(request):
    global ORIGINAL_SOURCE
    request.addfinalizer(cleanup)

    start_sh = f"{PROJECT}/start.sh"
    assert os.path.exists(start_sh), f"{start_sh} does not exist."
    assert os.access(start_sh, os.X_OK), f"{start_sh} is not executable."

    with open(SOURCE, "rb") as f:
        ORIGINAL_SOURCE = f.read()
    with open(SOURCE, "w") as f:
        f.write(instrumented_source())

    # Force start.sh/make to produce the library from the verifier-controlled source.
    if os.path.lexists(LIBRARY):
        if os.path.isdir(LIBRARY) and not os.path.islink(LIBRARY):
            shutil.rmtree(LIBRARY)
        else:
            os.remove(LIBRARY)

    subprocess.run([start_sh], cwd=PROJECT, check=True)
    time.sleep(3)
    yield


def test_makefile_exists():
    assert os.path.exists(f"{PROJECT}/Makefile"), "Makefile does not exist."


def test_package_management_setup_exists():
    server_dir = f"{PROJECT}/server"
    assert os.path.isdir(server_dir), "server directory does not exist."

    exact_names = {
        "requirements.txt", "pyproject.toml", "Pipfile", "poetry.lock",
        "package.json", "Gemfile", "go.mod", "Cargo.toml", "composer.json",
        "mix.exs", "pom.xml", "build.gradle", "build.gradle.kts",
        "Package.swift", "deno.json", "deno.jsonc", "pubspec.yaml",
        "stack.yaml", "cabal.project"
    }
    suffixes = (".csproj", ".fsproj", ".vbproj", ".cabal")
    manifests = [
        name for name in os.listdir(server_dir)
        if name in exact_names or name.endswith(suffixes)
    ]
    assert manifests, "No language package-management manifest was found in server/."
    assert any(os.path.isfile(os.path.join(server_dir, name)) for name in manifests), \
        "Package-management manifest is not a regular file."


def load_library():
    lib = ctypes.CDLL(LIBRARY)
    fn = lib.is_safe_payload
    fn.argtypes = [ctypes.c_char_p]
    fn.restype = ctypes.c_int
    return lib, fn


def test_shared_library_built_and_valid():
    assert os.path.exists(LIBRARY), f"Shared library {LIBRARY} was not built."
    assert os.path.isfile(LIBRARY), f"{LIBRARY} is not a regular file."
    with open(LIBRARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libsanitizer.so is not an ELF library."

    _, fn = load_library()
    assert fn(b"ordinary payload") == 1
    assert fn(b"x<script>y") == 0
    assert fn(b"x DROP TABLE accounts") == 0
    assert fn(b"x OR 1=1 y") == 0


def read_server_pid():
    assert os.path.exists(PID_FILE), "server.pid does not exist."
    with open(PID_FILE, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), "server.pid does not contain a valid integer PID."
    return int(pid_str)


def test_server_pid_exists_and_running():
    pid = read_server_pid()
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        pytest.fail(f"Process with PID {pid} is not running.")


def recv_exact(s, count):
    data = b""
    while len(data) < count:
        chunk = s.recv(count - len(data))
        if not chunk:
            raise EOFError("WebSocket connection closed unexpectedly")
        data += chunk
    return data


def ws_connect(host, port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    s.connect((host, port))
    key = base64.b64encode(os.urandom(16)).decode("utf-8")
    handshake = (
        f"GET / HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        f"Upgrade: websocket\r\n"
        f"Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        f"Sec-WebSocket-Version: 13\r\n\r\n"
    )
    s.sendall(handshake.encode("utf-8"))
    response = b""
    while b"\r\n\r\n" not in response:
        response += s.recv(4096)
    assert b"101 Switching Protocols" in response, "WebSocket handshake failed"
    return s


def ws_send(s, text):
    payload = text.encode("utf-8")
    length = len(payload)
    header = bytearray([0x81])
    if length < 126:
        header.append(length | 0x80)
    elif length < 65536:
        header.append(126 | 0x80)
        header.extend(struct.pack("!H", length))
    else:
        header.append(127 | 0x80)
        header.extend(struct.pack("!Q", length))

    mask = os.urandom(4)
    header.extend(mask)
    header.extend(payload[i] ^ mask[i % 4] for i in range(length))
    s.sendall(header)


def ws_recv(s):
    b1, b2 = recv_exact(s, 2)
    length = b2 & 0x7f
    if length == 126:
        length = struct.unpack("!H", recv_exact(s, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", recv_exact(s, 8))[0]
    mask = recv_exact(s, 4) if b2 & 0x80 else None
    payload = bytearray(recv_exact(s, length))
    if mask:
        for i in range(length):
            payload[i] ^= mask[i % 4]
    return payload.decode("utf-8")


def random_text(min_length=8, max_length=60):
    alphabet = string.ascii_letters + string.digits + " _-.:/"
    return "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(max_length - min_length + 1) + min_length))


def test_websocket_server_behavior_and_library_invocation():
    try:
        ws = ws_connect("127.0.0.1", 8765)
    except Exception as e:
        pytest.fail(f"Could not connect to WebSocket server on 127.0.0.1:8765: {e}")

    # Preserve the original fixed behavioral assertions.
    fixed_cases = [
        ("Hello World", "SAFE: Hello World"),
        ("<script>alert(1)</script>", "REJECTED"),
        ("SELECT * FROM users WHERE id=1 OR 1=1;", "REJECTED"),
    ]

    token = secrets.token_hex(20)
    randomized_messages = [
        f"{token}-{random_text()}",
        random_text() + "<script>" + random_text(),
        random_text() + "DROP TABLE" + random_text(),
        random_text() + "OR 1=1" + random_text(),
        token + "-" + random_text(180, 240),
    ]

    # Derive responses from the freshly built C artifact rather than a fixed answer list.
    _, sanitizer = load_library()
    randomized_cases = []
    for message in randomized_messages:
        result = sanitizer(message.encode("utf-8"))
        assert result in (0, 1)
        randomized_cases.append((message, f"SAFE: {message}" if result == 1 else "REJECTED"))

    # Discard direct ctypes calls; subsequent entries must come from server handling.
    with open(INVOKE_LOG, "w"):
        pass

    try:
        for message, expected in fixed_cases + randomized_cases:
            ws_send(ws, message)
            response = ws_recv(ws)
            assert response == expected, f"Expected {expected!r}, got {response!r}"
    finally:
        ws.close()

    deadline = time.time() + 2
    observed = []
    while time.time() < deadline:
        if os.path.exists(INVOKE_LOG):
            with open(INVOKE_LOG, "r") as f:
                observed = f.read().splitlines()
            if all(message in observed for message, _ in fixed_cases + randomized_cases):
                break
        time.sleep(0.05)

    for message, _ in fixed_cases + randomized_cases:
        assert message in observed, f"Server did not invoke is_safe_payload for {message!r}."


def test_server_process_has_shared_library_loaded():
    pid = read_server_pid()
    maps_path = f"/proc/{pid}/maps"
    assert os.path.exists(maps_path), "Cannot inspect the running server process mappings."
    with open(maps_path, "r", errors="replace") as f:
        mappings = f.read()
    assert "libsanitizer.so" in mappings, \
        "The server process has not dynamically loaded libsanitizer.so."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
