#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import socket
import base64
import subprocess
import time
import ctypes
import struct
import random
import string
import pytest

DONE = "/home/user/done.txt"
SO = "/home/user/rust_hasher/target/release/librust_hasher.so"
SCRIPT = "/home/user/artifact_server.py"
PORT = 8765


def adler_like(data):
    s1, s2 = 1, 0
    for byte in data:
        s1 = (s1 + byte) % 65521
        s2 = (s2 + s1) % 65521
    return f"{((s2 << 16) | s1):08x}"


def test_done_file():
    assert os.path.exists(DONE), f"Missing {DONE}"
    with open(DONE) as f:
        assert f.read().strip() == "READY"


def test_rust_compiled_and_ffi():
    assert os.path.isfile(SO), f"Missing compiled Rust library at {SO}"
    with open(SO, "rb") as f:
        assert f.read(4) == b"\\x7fELF", "Rust output is not an ELF shared library"
    lib = ctypes.CDLL(SO)
    calc = lib.calculate_artifact_checksum
    calc.argtypes = [ctypes.POINTER(ctypes.c_ubyte), ctypes.c_size_t]
    calc.restype = ctypes.c_void_p
    free = lib.free_checksum
    free.argtypes = [ctypes.c_void_p]
    free.restype = None
    for data in (b"", os.urandom(257), b"ffi-check-" + os.urandom(31)):
        buf = (ctypes.c_ubyte * max(1, len(data)))()
        if data:
            ctypes.memmove(buf, data, len(data))
        ptr = calc(buf, len(data))
        assert ptr, "calculate_artifact_checksum returned NULL"
        try:
            assert ctypes.string_at(ptr).decode("ascii") == adler_like(data)
        finally:
            free(ptr)


def test_server_script_exists():
    assert os.path.isfile(SCRIPT), f"Missing Python script at {SCRIPT}"


def recv_exact(sock, n):
    out = b""
    while len(out) < n:
        chunk = sock.recv(n - len(out))
        if not chunk:
            raise AssertionError("WebSocket closed unexpectedly")
        out += chunk
    return out


def ws_connect():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect(("localhost", PORT))
    key = base64.b64encode(os.urandom(16)).decode()
    request = (
        "GET / HTTP/1.1\r\n"
        f"Host: localhost:{PORT}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n\r\n"
    )
    s.sendall(request.encode())
    response = b""
    while b"\r\n\r\n" not in response:
        response += s.recv(4096)
    assert b"101 Switching Protocols" in response
    return s


def ws_send(sock, obj):
    payload = json.dumps(obj).encode()
    frame = bytearray([0x81])
    mask = os.urandom(4)
    n = len(payload)
    if n < 126:
        frame.append(0x80 | n)
    elif n < 65536:
        frame.append(0x80 | 126)
        frame.extend(struct.pack("!H", n))
    else:
        frame.append(0x80 | 127)
        frame.extend(struct.pack("!Q", n))
    frame.extend(mask)
    frame.extend(byte ^ mask[i % 4] for i, byte in enumerate(payload))
    sock.sendall(frame)


def ws_recv(sock):
    header = recv_exact(sock, 2)
    assert (header[0] & 0x0f) == 1, "Expected text WebSocket frame"
    n = header[1] & 0x7f
    if n == 126:
        n = struct.unpack("!H", recv_exact(sock, 2))[0]
    elif n == 127:
        n = struct.unpack("!Q", recv_exact(sock, 8))[0]
    mask = recv_exact(sock, 4) if header[1] & 0x80 else None
    data = recv_exact(sock, n)
    if mask:
        data = bytes(byte ^ mask[i % 4] for i, byte in enumerate(data))
    return json.loads(data.decode())


def assert_response(response, build_id, files, previous, contents):
    current = {path: adler_like(contents[path]) for path in files}
    expected = {
        "id": build_id,
        "sorted_hashes": [
            {"file": path, "hash": current[path]} for path in sorted(files)
        ],
        "diff": {
            "added": sorted(set(current) - set(previous)),
            "removed": sorted(set(previous) - set(current)),
            "modified": sorted(
                path for path in set(current) & set(previous)
                if current[path] != previous[path]
            ),
        },
    }
    assert response == expected
    return current


def test_websocket_server_logic_and_ffi_usage():
    test_dir = "/home/user/artifacts_test"
    os.makedirs(test_dir, exist_ok=True)
    token = "".join(random.choice(string.ascii_letters) for _ in range(10))
    paths = [os.path.join(test_dir, name) for name in
             (f"z_{token}.bin", f"a_{token}.bin", f"m_{token}.bin", f"q_{token}.bin")]
    contents = {
        paths[0]: os.urandom(83) + b"first",
        paths[1]: b"\\x00\\xff" + os.urandom(129),
        paths[2]: os.urandom(17),
        paths[3]: os.urandom(301),
    }
    for path, data in contents.items():
        with open(path, "wb") as f:
            f.write(data)

    # Interpose only the server process's Rust symbols. Correct output alone is
    # insufficient: both calculate and free must actually be called.
    shim_c = "/tmp/ffi_audit.c"
    shim_so = "/tmp/ffi_audit.so"
    log_path = "/tmp/ffi_audit.log"
    open(log_path, "w").close()
    with open(shim_c, "w") as f:
        f.write(r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
typedef char *(*calc_t)(const unsigned char *, size_t);
typedef void (*free_t)(char *);
char *calculate_artifact_checksum(const unsigned char *data, size_t len) {
    calc_t real = (calc_t)dlsym(RTLD_NEXT, "calculate_artifact_checksum");
    FILE *f = fopen(getenv("FFI_AUDIT_LOG"), "a");
    if (f) { fprintf(f, "C %zu\\n", len); fclose(f); }
    if (!real) _exit(91);
    return real(data, len);
}
void free_checksum(char *ptr) {
    free_t real = (free_t)dlsym(RTLD_NEXT, "free_checksum");
    FILE *f = fopen(getenv("FFI_AUDIT_LOG"), "a");
    if (f) { fprintf(f, "F\\n"); fclose(f); }
    if (!real) _exit(92);
    real(ptr);
}
''')
    subprocess.run(["cc", "-shared", "-fPIC", "-o", shim_so, shim_c, "-ldl"], check=True)
    env = os.environ.copy()
    env["LD_PRELOAD"] = shim_so
    env["FFI_AUDIT_LOG"] = log_path
    proc = subprocess.Popen(["python3", SCRIPT], env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    sock = None
    try:
        deadline = time.time() + 8
        while True:
            try:
                sock = ws_connect()
                break
            except OSError:
                if proc.poll() is not None:
                    out, err = proc.communicate()
                    pytest.fail(f"Server exited early: {out!r} {err!r}")
                if time.time() > deadline:
                    pytest.fail("Server did not listen on port 8765")
                time.sleep(.1)

        previous = {}
        first = [paths[0], paths[2], paths[1]]  # deliberately unsorted
        ws_send(sock, {"id": "random-" + token + "-1", "files": first})
        previous = assert_response(ws_recv(sock), "random-" + token + "-1",
                                   first, previous, contents)

        contents[paths[1]] = os.urandom(211) + token.encode()
        with open(paths[1], "wb") as f:
            f.write(contents[paths[1]])
        second = [paths[3], paths[1], paths[2]]
        ws_send(sock, {"id": "random-" + token + "-2", "files": second})
        previous = assert_response(ws_recv(sock), "random-" + token + "-2",
                                   second, previous, contents)

        third = [paths[2]]
        ws_send(sock, {"id": "random-" + token + "-3", "files": third})
        assert_response(ws_recv(sock), "random-" + token + "-3",
                        third, previous, contents)
        sock.close()
        sock = None
        time.sleep(.2)

        with open(log_path) as f:
            events = [line.strip() for line in f if line.strip()]
        calls = [event for event in events if event.startswith("C ")]
        frees = [event for event in events if event == "F"]
        expected_lengths = [len(contents[p]) for p in first + second + third]
        actual_lengths = [int(event.split()[1]) for event in calls]
        assert actual_lengths == expected_lengths, "Server did not call Rust checksum once per file with the raw byte lengths"
        assert len(frees) == len(calls), "Server must call free_checksum for every returned checksum"
    finally:
        if sock:
            sock.close()
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
