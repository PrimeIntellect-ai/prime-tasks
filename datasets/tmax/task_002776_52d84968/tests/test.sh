#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import os
from pathlib import Path
import random
import re
import select
import socket
import subprocess
import time

import pytest

AGENT_PROG = "/home/user/encoder"
AGENT_SOURCE = "/home/user/encoder.cpp"
PROP_SOURCE = "/home/user/prop_test.cpp"
RESULTS_LOG = "/home/user/test_results.log"
ORACLE_PROG = "/app/legacy_asset_encoder"
REBUILT_PROG = "/tmp/encoder_from_source"
PROP_PROG = "/tmp/prop_test_from_source"


def clean_env():
    env = os.environ.copy()
    env.pop("WS_PORT", None)
    return env


def run_program(path, data, env=None, timeout=2):
    return subprocess.run(
        [path], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        env=env or clean_env(), timeout=timeout
    )


def test_agent_program_exists():
    assert os.path.exists(AGENT_PROG), f"Agent program {AGENT_PROG} does not exist."
    assert os.path.isfile(AGENT_PROG), f"{AGENT_PROG} is not a file."
    assert os.access(AGENT_PROG, os.X_OK), f"{AGENT_PROG} is not executable."
    with open(AGENT_PROG, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{AGENT_PROG} is not a compiled Linux executable."


def test_cpp_source_exists_compiles_and_implements_encoder():
    assert os.path.isfile(AGENT_SOURCE), f"Required source {AGENT_SOURCE} is missing."
    assert os.path.getsize(AGENT_SOURCE) > 0, f"{AGENT_SOURCE} is empty."

    compile_proc = subprocess.run(
        ["g++", "-std=c++17", "-O2", AGENT_SOURCE, "-o", REBUILT_PROG,
         "-pthread", "-lwebsockets", "-lboost_system"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert compile_proc.returncode == 0, (
        "encoder.cpp did not compile as a standalone C++ program:\n" +
        compile_proc.stderr.decode(errors="replace")
    )

    rng = random.Random(918273)
    for i in range(64):
        data = bytes(rng.getrandbits(8) for _ in range(rng.randint(0, 4096)))
        expected = run_program(ORACLE_PROG, data)
        actual = run_program(REBUILT_PROG, data)
        assert expected.stdout == actual.stdout, (
            f"Program rebuilt from encoder.cpp differs from the oracle on source test {i}."
        )


def test_fuzz_equivalence():
    oracle_prog = ORACLE_PROG
    agent_prog = AGENT_PROG

    assert os.path.exists(oracle_prog), f"Oracle program {oracle_prog} is missing."
    assert os.access(oracle_prog, os.X_OK), f"Oracle program {oracle_prog} is not executable."

    # Use a fixed seed for reproducibility
    rng = random.Random(42)

    # 1000 iterations
    for i in range(1000):
        # Random length between 0 and 8192
        length = rng.randint(0, 8192)

        # Generate random bytes
        input_data = bytearray(rng.getrandbits(8) for _ in range(length))

        # Run oracle
        env = os.environ.copy()
        env.pop("WS_PORT", None) # Ensure WS_PORT is unset

        try:
            oracle_proc = subprocess.run(
                [oracle_prog],
                input=input_data,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
                timeout=2
            )
            oracle_out = oracle_proc.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle program timed out on iteration {i} (length {length})")

        # Run agent
        try:
            agent_proc = subprocess.run(
                [agent_prog],
                input=input_data,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
                timeout=2
            )
            agent_out = agent_proc.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent program timed out on iteration {i} (length {length})")

        # Assert equivalence
        if oracle_out != agent_out:
            # Provide a helpful error message but don't dump 8KB of binary to console directly
            err_msg = (
                f"Output mismatch on iteration {i} (input length {length}).\n"
                f"Oracle output length: {len(oracle_out)}, Agent output length: {len(agent_out)}\n"
            )
            if len(input_data) < 64:
                err_msg += f"Input data (hex): {input_data.hex()}\n"
                err_msg += f"Oracle out (hex): {oracle_out.hex()}\n"
                err_msg += f"Agent out (hex):  {agent_out.hex()}"
            pytest.fail(err_msg)


def test_property_test_source_and_results():
    assert os.path.isfile(PROP_SOURCE), f"Required property test {PROP_SOURCE} is missing."
    assert os.path.getsize(PROP_SOURCE) > 0, f"{PROP_SOURCE} is empty."
    assert os.path.isfile(RESULTS_LOG), f"Required result log {RESULTS_LOG} is missing."
    assert os.path.getsize(RESULTS_LOG) > 0, f"{RESULTS_LOG} is empty."

    source = Path(PROP_SOURCE).read_text(errors="replace")
    assert re.search(r"(?:__asm__|\basm)\s*(?:volatile\s*)?\(", source), (
        "prop_test.cpp does not contain an inline-assembly implementation."
    )
    assert re.search(r"mt19937|random_device|\brand\s*\(", source), (
        "prop_test.cpp does not generate randomized test data."
    )
    assert re.search(r"\b100\b", source), (
        "prop_test.cpp does not specify the required 100 randomized cases."
    )
    assert re.search(r"\bassert\s*\(|!=|mismatch|abort\s*\(", source, re.IGNORECASE), (
        "prop_test.cpp does not appear to check for disagreement."
    )

    compile_proc = subprocess.run(
        ["g++", "-std=c++17", "-O2", PROP_SOURCE, "-o", PROP_PROG, "-pthread"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert compile_proc.returncode == 0, (
        "prop_test.cpp did not compile as a standalone C++ test:\n" +
        compile_proc.stderr.decode(errors="replace")
    )

    with open(RESULTS_LOG, "wb") as log_file:
        try:
            prop_proc = subprocess.run(
                [PROP_PROG], cwd="/home/user", stdout=log_file,
                stderr=subprocess.PIPE, timeout=20
            )
        except subprocess.TimeoutExpired:
            pytest.fail("The property-based test timed out.")
    assert prop_proc.returncode == 0, (
        "The property-based test reported failure:\n" +
        prop_proc.stderr.decode(errors="replace")
    )
    assert os.path.getsize(RESULTS_LOG) > 0, (
        "The executed property test did not write a result summary to test_results.log."
    )


def recv_until(sock, marker, limit=65536):
    data = bytearray()
    while marker not in data:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data.extend(chunk)
        assert len(data) <= limit, "WebSocket HTTP request was unexpectedly large."
    return bytes(data)


def recv_exact(sock, count):
    data = bytearray()
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        if not chunk:
            raise AssertionError("WebSocket connection closed before a complete frame arrived.")
        data.extend(chunk)
    return bytes(data)


def verify_websocket(program):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 0))
    server.listen(1)
    server.settimeout(5)
    port = server.getsockname()[1]

    env = os.environ.copy()
    env["WS_PORT"] = str(port)
    payload = b"websocket-order-check\x00\xff"
    proc = subprocess.Popen(
        [program], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, env=env
    )
    try:
        proc.stdin.write(payload)
        proc.stdin.close()
        proc.stdin = None

        conn, _ = server.accept()
        with conn:
            conn.settimeout(5)
            request = recv_until(conn, b"\r\n\r\n")
            assert request.startswith(b"GET "), "No WebSocket HTTP upgrade request was received."
            headers = {}
            for line in request.decode("latin1").split("\r\n")[1:]:
                if ":" in line:
                    name, value = line.split(":", 1)
                    headers[name.strip().lower()] = value.strip()
            assert headers.get("upgrade", "").lower() == "websocket"
            assert "upgrade" in headers.get("connection", "").lower()
            key = headers.get("sec-websocket-key")
            assert key, "WebSocket upgrade request omitted Sec-WebSocket-Key."

            # The encoder must not begin producing encoded stdout while the
            # WebSocket handshake and BUILD_START send are still pending.
            ready, _, _ = select.select([proc.stdout], [], [], 0.25)
            assert not ready, "Encoder produced binary output before WebSocket startup completed."

            accept = base64.b64encode(hashlib.sha1(
                (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")
            ).digest()).decode("ascii")
            response = (
                "HTTP/1.1 101 Switching Protocols\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
            ).encode("ascii")
            conn.sendall(response)

            first = recv_exact(conn, 2)
            assert first[0] & 0x80, "BUILD_START frame was not final."
            assert first[0] & 0x0f == 0x1, "BUILD_START was not sent as a text frame."
            masked = bool(first[1] & 0x80)
            assert masked, "Client WebSocket frames must be masked."
            length = first[1] & 0x7f
            if length == 126:
                length = int.from_bytes(recv_exact(conn, 2), "big")
            elif length == 127:
                length = int.from_bytes(recv_exact(conn, 8), "big")
            mask = recv_exact(conn, 4)
            encoded = recv_exact(conn, length)
            message = bytes(b ^ mask[i % 4] for i, b in enumerate(encoded))
            assert message == b"BUILD_START", f"Unexpected WebSocket message: {message!r}"

        stdout, stderr = proc.communicate(timeout=5)
        assert proc.returncode == 0, stderr.decode(errors="replace")
        expected = run_program(ORACLE_PROG, payload).stdout
        assert stdout == expected, "WS_PORT changed or corrupted the encoder's binary output."
    finally:
        server.close()
        if proc.poll() is None:
            proc.kill()
            proc.wait()


def test_websocket_build_start_behavior():
    verify_websocket(AGENT_PROG)
    verify_websocket(REBUILT_PROG)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
