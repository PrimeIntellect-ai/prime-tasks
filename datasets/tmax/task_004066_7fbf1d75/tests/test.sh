#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import os
import random
import signal
import subprocess
import sys
import time
from fractions import Fraction

import websockets

SERVER_PATH = "/home/user/ws_mock.py"
CLIENT_PATH = "/home/user/client.py"
OUTPUT_PATH = "/home/user/ws_output.txt"
PORT = 9090


def test_ws_mock_script_exists():
    """Verify that the WebSocket mock server script exists."""
    filepath = SERVER_PATH
    assert os.path.isfile(filepath), f"Expected server script at {filepath} does not exist."


def test_client_script_exists():
    """Verify that the WebSocket client script exists."""
    filepath = CLIENT_PATH
    assert os.path.isfile(filepath), f"Expected client script at {filepath} does not exist."


def test_ws_output_correct():
    """Verify that the output file exists and contains the correct evaluated result."""
    filepath = OUTPUT_PATH
    assert os.path.isfile(filepath), f"Expected output file at {filepath} does not exist."

    with open(filepath, "r") as f:
        content = f.read().strip()

    expected_output = "22.0"
    assert content == expected_output, (
        f"Output file {filepath} content is incorrect. "
        f"Expected '{expected_output}', but got '{content}'."
    )


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def clear_port(port):
    for sig, delay in ((signal.SIGTERM, 0.5), (signal.SIGKILL, 0.2)):
        pids = listener_pids(port)
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(delay)
    assert not listener_pids(port), f"Could not free TCP port {port}"


def make_expression(rng, depth):
    if depth == 0:
        value = rng.randint(1, 9)
        return str(value), Fraction(value)

    op = rng.choice(["+", "-", "*", "/"])
    left_text, left_value = make_expression(rng, depth - 1)
    right_text, right_value = make_expression(rng, depth - 1)
    if op == "/" and right_value == 0:
        right_text, right_value = str(rng.randint(1, 9)), Fraction(rng.randint(1, 9))

    if op == "+":
        value = left_value + right_value
    elif op == "-":
        value = left_value - right_value
    elif op == "*":
        value = left_value * right_value
    else:
        value = left_value / right_value
    return f"{op} {left_text} {right_text}", value


async def exercise_server(cases):
    for expression, expected in cases:
        last_error = None
        for _ in range(40):
            try:
                async with websockets.connect("ws://localhost:9090", open_timeout=1) as ws:
                    await ws.send(expression)
                    response = await asyncio.wait_for(ws.recv(), timeout=3)
                    assert isinstance(response, str), "Server response was not text"
                    assert response == expected, (
                        f"For prefix expression {expression!r}, expected {expected!r} "
                        f"but received {response!r}"
                    )
                    last_error = None
                    break
            except (OSError, asyncio.TimeoutError) as exc:
                last_error = exc
                await asyncio.sleep(0.1)
        if last_error is not None:
            raise AssertionError(f"Server did not become usable on ws://localhost:9090: {last_error}")


async def exercise_client():
    received = []

    async def handler(ws, *args):
        message = await asyncio.wait_for(ws.recv(), timeout=5)
        received.append(message)
        await ws.send("22.0" if message == "- * + 5 10 2 8" else "unexpected expression")

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    async with websockets.serve(handler, "localhost", PORT):
        proc = await asyncio.create_subprocess_exec(
            sys.executable,
            CLIENT_PATH,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=10)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.wait()
            raise AssertionError("client.py did not finish within 10 seconds")

    assert proc.returncode == 0, (
        f"client.py exited with status {proc.returncode}: "
        f"{stderr.decode(errors='replace')}"
    )
    assert received == ["- * + 5 10 2 8"], (
        "client.py must connect to ws://localhost:9090 and send the exact required expression; "
        f"received {received!r}"
    )
    assert os.path.isfile(OUTPUT_PATH), f"Expected output file at {OUTPUT_PATH} does not exist."
    with open(OUTPUT_PATH) as f:
        content = f.read().strip()
    assert content == "22.0", f"Expected client to save '22.0', but got {content!r}"


def test_server_and_client_behavior():
    clear_port(PORT)

    rng = random.SystemRandom()
    cases = []
    # Ensure every required operator is exercised, with values chosen at verification time.
    a, b, c, d = [rng.randint(2, 9) for _ in range(4)]
    explicit = [
        (f"+ {a} {b}", Fraction(a + b)),
        (f"- {a} {b}", Fraction(a - b)),
        (f"* + {a} {b} {c}", Fraction((a + b) * c)),
        (f"/ * {a} {b} {c}", Fraction(a * b, c)),
        (f"- * + {a} {b} {c} {d}", Fraction((a + b) * c - d)),
    ]
    for expression, value in explicit:
        cases.append((expression, f"{float(value):.1f}"))
    for _ in range(12):
        expression, value = make_expression(rng, rng.choice([2, 3]))
        cases.append((expression, f"{float(value):.1f}"))

    log = open("/tmp/ws_mock_verifier.log", "wb")
    server = subprocess.Popen(
        [sys.executable, SERVER_PATH],
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    try:
        asyncio.run(exercise_server(cases))
    finally:
        if server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=3)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=3)
        log.close()
        clear_port(PORT)

    asyncio.run(exercise_client())

    # Restore the required background server after the verifier's isolated client test.
    clear_port(PORT)
    background_log = open("/tmp/ws_mock_background.log", "ab")
    subprocess.Popen(
        [sys.executable, SERVER_PATH],
        stdout=background_log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    background_log.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
