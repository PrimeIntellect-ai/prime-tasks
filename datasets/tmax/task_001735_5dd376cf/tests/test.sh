#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import pathlib
import secrets
import shutil
import signal
import socket
import struct
import subprocess
import tempfile
import time

import pytest

CPP_FILE = "/home/user/ws_firewall.cpp"
BIN_FILE = "/home/user/ws_firewall_bin"
BENCH_FILE = "/home/user/bench_results.txt"
MONGOOSE_DIR = "/app/vendored/mongoose"
MONGOOSE_LIB = os.path.join(MONGOOSE_DIR, "libmongoose.a")


def test_files_exist():
    assert os.path.isfile(CPP_FILE), f"C++ source file {CPP_FILE} is missing."
    assert os.path.isfile(BIN_FILE), f"Compiled binary {BIN_FILE} is missing."
    assert os.path.isfile(BENCH_FILE), f"Benchmark results {BENCH_FILE} is missing."

    with open(BENCH_FILE, "r") as f:
        content = f.read().strip()
    assert len(content) > 0, f"Benchmark results file {BENCH_FILE} is empty."


def test_makefile_builds_static_archive():
    makefile = os.path.join(MONGOOSE_DIR, "Makefile")
    assert os.path.isfile(makefile), "Vendored Mongoose Makefile is missing."
    assert os.path.isfile(MONGOOSE_LIB), "make static did not leave libmongoose.a in the vendored directory."

    existing = subprocess.run(["ar", "t", MONGOOSE_LIB], capture_output=True, text=True)
    assert existing.returncode == 0 and existing.stdout.strip(), \
        f"Existing libmongoose.a is not a valid nonempty archive: {existing.stderr}"

    with tempfile.TemporaryDirectory() as td:
        for name in ("Makefile", "mongoose.c", "mongoose.h"):
            shutil.copy2(os.path.join(MONGOOSE_DIR, name), os.path.join(td, name))
        result = subprocess.run(
            ["make", "static"], cwd=td, capture_output=True, text=True, timeout=60
        )
        assert result.returncode == 0, \
            f"The vendored Makefile's static target failed:\n{result.stdout}\n{result.stderr}"
        archive = os.path.join(td, "libmongoose.a")
        assert os.path.isfile(archive), "make static did not produce libmongoose.a."
        listing = subprocess.run(["ar", "t", archive], capture_output=True, text=True)
        assert listing.returncode == 0 and listing.stdout.strip(), \
            f"make static produced an invalid or empty archive: {listing.stderr}"


def test_static_binary():
    result = subprocess.run(["file", BIN_FILE], capture_output=True, text=True)
    assert "statically linked" in result.stdout.lower(), \
        f"Binary {BIN_FILE} is not statically linked. 'file' output: {result.stdout}"


def test_source_and_binary_use_mongoose():
    source = pathlib.Path(CPP_FILE).read_text(errors="replace")
    assert "mongoose.h" in source, "The server source does not include the vendored Mongoose API."
    for api in ("mg_http_listen", "mg_ws_upgrade", "mg_ws_send"):
        assert api in source, f"The server source does not use required Mongoose API {api}."

    archive_symbols = subprocess.run(
        ["nm", "-g", MONGOOSE_LIB], capture_output=True, text=True
    )
    assert archive_symbols.returncode == 0 and "mg_ws_send" in archive_symbols.stdout, \
        "libmongoose.a does not contain the expected Mongoose implementation."

    binary_symbols = subprocess.run(
        ["nm", "-a", BIN_FILE], capture_output=True, text=True
    )
    assert binary_symbols.returncode == 0, \
        "Unable to inspect the submitted binary for linked Mongoose code."
    for symbol in ("mg_mgr_init", "mg_http_listen", "mg_ws_send"):
        assert symbol in binary_symbols.stdout, \
            f"The final binary does not contain linked Mongoose symbol {symbol}."


def _kill_port_8080_listeners():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].endswith(":1F90") and fields[3] == "0A":
                inodes.add(fields[9])

    victims = set()
    for proc_dir in pathlib.Path("/proc").glob("[0-9]*"):
        fd_dir = proc_dir / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(proc_dir.name))
                    break
        except OSError:
            continue

    for pid in victims:
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    if victims:
        time.sleep(0.3)


@pytest.fixture(scope="session")
def running_server():
    _kill_port_8080_listeners()
    proc = subprocess.Popen(
        [BIN_FILE],
        cwd="/home/user",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    deadline = time.time() + 8
    last_error = None
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.3):
                break
        except OSError as exc:
            last_error = exc
            time.sleep(0.1)
    else:
        raise AssertionError(f"Executing {BIN_FILE} did not start a server on port 8080: {last_error}")

    # Deliberately do not terminate it: the task requires the server to remain running.
    return proc


def _recv_exact(sock, count, initial=b""):
    data = bytearray(initial)
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        if not chunk:
            raise RuntimeError("Connection closed while receiving a WebSocket frame")
        data.extend(chunk)
    return bytes(data)


def _connect_ws(host="127.0.0.1", port=8080):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    s.connect((host, port))
    key = base64.b64encode(os.urandom(16)).decode("ascii")
    request = (
        f"GET / HTTP/1.1\r\nHost: {host}:{port}\r\n"
        "Upgrade: websocket\r\nConnection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
    )
    s.sendall(request.encode("ascii"))
    response = b""
    while b"\r\n\r\n" not in response:
        chunk = s.recv(4096)
        if not chunk:
            s.close()
            raise RuntimeError("Connection closed during WebSocket handshake")
        response += chunk
    headers, remainder = response.split(b"\r\n\r\n", 1)
    if b"101 Switching Protocols" not in headers:
        s.close()
        raise RuntimeError(f"WebSocket handshake failed: {headers!r}")
    return s, remainder


def _send_frame(sock, message):
    payload = message.encode("utf-8")
    length = len(payload)
    frame = bytearray([0x81])
    if length < 126:
        frame.append(0x80 | length)
    elif length < 65536:
        frame.append(0x80 | 126)
        frame.extend(struct.pack(">H", length))
    else:
        frame.append(0x80 | 127)
        frame.extend(struct.pack(">Q", length))
    mask = os.urandom(4)
    frame.extend(mask)
    frame.extend(byte ^ mask[i % 4] for i, byte in enumerate(payload))
    sock.sendall(frame)


def _recv_frame(sock, initial=b""):
    header = _recv_exact(sock, 2, initial[:2]) if len(initial) < 2 else initial[:2]
    remainder = initial[2:] if len(initial) >= 2 else b""
    b1, b2 = header
    length = b2 & 0x7f
    if length == 126:
        ext = _recv_exact(sock, 2, remainder[:2])
        remainder = remainder[2:] if len(remainder) >= 2 else b""
        length = struct.unpack(">H", ext)[0]
    elif length == 127:
        ext = _recv_exact(sock, 8, remainder[:8])
        remainder = remainder[8:] if len(remainder) >= 8 else b""
        length = struct.unpack(">Q", ext)[0]
    masked = bool(b2 & 0x80)
    mask = b""
    if masked:
        mask = _recv_exact(sock, 4, remainder[:4])
        remainder = remainder[4:] if len(remainder) >= 4 else b""
    payload = _recv_exact(sock, length, remainder[:length])
    if masked:
        payload = bytes(byte ^ mask[i % 4] for i, byte in enumerate(payload))
    assert (b1 & 0x0f) == 1, f"Expected a text WebSocket frame, got opcode {b1 & 0x0f}."
    return payload.decode("utf-8", errors="strict")


def ws_send_recv(host, port, message):
    sock, remainder = _connect_ws(host, port)
    try:
        _send_frame(sock, message)
        return _recv_frame(sock, remainder)
    finally:
        sock.close()


def test_benchmark_results_match_benchmark_execution(running_server):
    result = subprocess.run(
        ["/app/bench_tool.sh"], capture_output=True, timeout=30, check=True
    )
    actual = pathlib.Path(BENCH_FILE).read_bytes()
    assert actual == result.stdout, \
        "bench_results.txt is not the redirected standard output of /app/bench_tool.sh."


def test_adversarial_corpus(running_server):
    evil_dir = "/app/corpus/evil"
    clean_dir = "/app/corpus/clean"

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    evil_bypassed = []
    clean_modified = []

    for f in evil_files:
        with open(os.path.join(evil_dir, f), "r") as file:
            content = file.read()
        try:
            if ws_send_recv("127.0.0.1", 8080, content) != "REJECT":
                evil_bypassed.append(f)
        except Exception as exc:
            evil_bypassed.append(f"{f} (Error: {exc})")

    for f in clean_files:
        with open(os.path.join(clean_dir, f), "r") as file:
            content = file.read()
        try:
            if ws_send_recv("127.0.0.1", 8080, content) != "ACK":
                clean_modified.append(f)
        except Exception as exc:
            clean_modified.append(f"{f} (Error: {exc})")

    error_msg = ""
    if evil_bypassed:
        error_msg += f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}. "
    if clean_modified:
        error_msg += f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}."
    assert not evil_bypassed and not clean_modified, error_msg.strip()


def test_randomized_substring_filter_and_persistent_session(running_server):
    cases = [
        "", "<script", "script>", "<Script>", "<script >", "DROP  TABLE",
        "drop table", "DROPTABLE", "prefix DROP TABLEsuffix",
        "x<script>y", "DROP TABLE", "<script>",
        "A" * 300, "B" * 180 + "<script>" + "C" * 180,
        "D" * 260 + "DROP TABLE" + "E" * 260,
    ]

    for _ in range(40):
        left = secrets.token_urlsafe(18)
        right = secrets.token_urlsafe(21)
        choice = secrets.randbelow(4)
        if choice == 0:
            payload = left + "<script>" + right
        elif choice == 1:
            payload = left + "DROP TABLE" + right
        elif choice == 2:
            payload = left + "<script" + right + "drop table"
        else:
            payload = left + "safe telemetry " + right
        cases.append(payload)

    sock, remainder = _connect_ws()
    try:
        for index, payload in enumerate(cases):
            expected = "REJECT" if ("<script>" in payload or "DROP TABLE" in payload) else "ACK"
            _send_frame(sock, payload)
            response = _recv_frame(sock, remainder if index == 0 else b"")
            remainder = b""
            assert response == expected, \
                f"Wrong response for dynamically generated payload {payload!r}: expected {expected}, got {response!r}"
    finally:
        sock.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
