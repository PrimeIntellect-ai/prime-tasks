#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import ctypes
import os
import secrets
import signal
import subprocess
import sys
import time

import websockets


def expected_result(value):
    return " ".join(word.upper()[::-1] for word in value.split())


def test_build_script():
    """Verify build.sh exists, runs successfully, and creates libprocessor.so."""
    build_script = "/home/user/build.sh"
    so_file = "/home/user/libprocessor.so"

    assert os.path.isfile(build_script), f"{build_script} is missing."

    # Remove the .so file if it exists to ensure build.sh actually creates it
    if os.path.exists(so_file):
        os.remove(so_file)

    result = subprocess.run(["bash", build_script], capture_output=True, cwd="/home/user")
    assert result.returncode == 0, f"build.sh failed to execute. stderr: {result.stderr.decode()}"

    assert os.path.isfile(so_file), f"build.sh did not produce {so_file}."


def test_server_script_exists():
    """Verify server.py exists."""
    assert os.path.isfile("/home/user/server.py"), "/home/user/server.py is missing."


def test_shared_library_is_valid_and_processes_data():
    """Load the produced ELF shared library and call ProcessData independently."""
    so_file = "/home/user/libprocessor.so"
    assert os.path.isfile(so_file), f"{so_file} is missing."
    with open(so_file, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{so_file} is not an ELF library."

    library = ctypes.CDLL(so_file)
    assert hasattr(library, "ProcessData"), "ProcessData is not exported by libprocessor.so."
    process_data = library.ProcessData
    process_data.argtypes = [ctypes.c_char_p]
    process_data.restype = ctypes.c_char_p

    cases = [
        "polyglot concurrent pipeline",
        f"runtime{secrets.token_hex(6)} websocket{secrets.token_hex(6)}",
        f"alpha{secrets.token_hex(4)} beta{secrets.token_hex(4)} gamma{secrets.token_hex(4)}",
    ]
    for value in cases:
        result = process_data(value.encode("utf-8"))
        assert result is not None, "ProcessData returned NULL."
        actual = result.decode("utf-8")
        assert actual == expected_result(value), (
            f"ProcessData({value!r}) returned {actual!r}, expected {expected_result(value)!r}."
        )


def test_websocket_server_independently():
    """Start server.py, connect as a real client, and test runtime-derived inputs."""
    server = subprocess.Popen(
        [sys.executable, "/home/user/server.py"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )

    exact = "polyglot concurrent pipeline"
    dynamic_cases = [
        f"socket{secrets.token_hex(7)} concurrent{secrets.token_hex(7)}",
        f"red{secrets.token_hex(5)} green{secrets.token_hex(5)} blue{secrets.token_hex(5)}",
    ]

    async def connect_with_retry():
        deadline = time.monotonic() + 12
        last_error = None
        while time.monotonic() < deadline:
            if server.poll() is not None:
                raise AssertionError(f"server.py exited early with status {server.returncode}")
            try:
                return await asyncio.wait_for(
                    websockets.connect("ws://localhost:8765"), timeout=1
                )
            except Exception as exc:
                last_error = exc
                await asyncio.sleep(0.15)
        raise AssertionError(f"Could not connect to the WebSocket server: {last_error}")

    async def exercise():
        cases = [exact] + dynamic_cases
        for index, message in enumerate(cases):
            if index == 0:
                connection = await connect_with_retry()
            else:
                connection = await asyncio.wait_for(
                    websockets.connect("ws://localhost:8765"), timeout=3
                )
            try:
                await asyncio.wait_for(connection.send(message), timeout=3)
                response = await asyncio.wait_for(connection.recv(), timeout=5)
            finally:
                await connection.close()
            expected = expected_result(message)
            assert response == expected, (
                f"Server returned {response!r} for {message!r}; expected {expected!r}."
            )

    try:
        asyncio.run(exercise())
        assert server.poll() is None, "server.py did not continue running after requests."
    finally:
        try:
            os.killpg(server.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            server.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(server.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            server.communicate(timeout=5)


def test_test_server_script():
    """Verify test_server.py exists, passes pytest, and creates the correct log file."""
    test_script = "/home/user/test_server.py"
    log_file = "/home/user/test_result.log"

    assert os.path.isfile(test_script), f"{test_script} is missing."

    # Remove the log file if it exists to ensure the test creates it
    if os.path.exists(log_file):
        os.remove(log_file)

    result = subprocess.run(
        ["python3", "-m", "pytest", test_script],
        capture_output=True,
        cwd="/home/user"
    )
    assert result.returncode == 0, f"pytest on {test_script} failed.\nstdout: {result.stdout.decode()}\nstderr: {result.stderr.decode()}"

    assert os.path.isfile(log_file), f"{log_file} was not created by the test."

    with open(log_file, "r") as f:
        content = f.read().strip()

    assert content == "TEST PASSED", f"Expected 'TEST PASSED' in {log_file}, but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
