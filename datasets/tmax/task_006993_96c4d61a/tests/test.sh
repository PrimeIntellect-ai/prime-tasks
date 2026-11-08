#!/bin/bash
set -u
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import ctypes
import hashlib
import os
import secrets
import signal
import subprocess
import time

import pytest
import websockets

C_DIR = "/home/user/hybrid_project/c_lib"
RUST_DIR = "/home/user/hybrid_project/rust_server"
MAKEFILE = os.path.join(C_DIR, "Makefile")
SO_PATH = os.path.join(C_DIR, "libtransform.so")
SERVER_PATH = os.path.join(RUST_DIR, "target", "debug", "rust_server")
RESPONSE_FILE = "/home/user/ws_response.txt"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def assert_elf(path, expected_type):
    with open(path, "rb") as f:
        header = f.read(20)
    assert header[:4] == b"\x7fELF", f"{path} is not an ELF artifact."
    assert len(header) >= 18, f"{path} has a truncated ELF header."
    byteorder = "little" if header[5] == 1 else "big"
    elf_type = int.from_bytes(header[16:18], byteorder)
    assert elf_type in expected_type, f"{path} has the wrong ELF artifact type."


def test_makefile_patched():
    assert os.path.isfile(MAKEFILE), f"{MAKEFILE} does not exist."
    with open(MAKEFILE, "r") as f:
        content = f.read()
    assert "-shared -fPIC" in content, "Makefile was not correctly patched with -shared and -fPIC flags."


def test_shared_library_compiled_and_functional():
    assert os.path.isfile(SO_PATH), f"Shared library {SO_PATH} was not compiled."
    assert os.access(SO_PATH, os.R_OK), f"Shared library {SO_PATH} is not readable."
    assert_elf(SO_PATH, {3})  # ET_DYN

    before = sha256(SO_PATH)
    result = subprocess.run(["make"], cwd=C_DIR, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=30)
    assert result.returncode == 0, f"make failed:\n{result.stdout}"
    assert sha256(SO_PATH) == before, "libtransform.so was not an up-to-date product of the Makefile."

    symbols = subprocess.run(["readelf", "-Ws", SO_PATH], text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10)
    assert symbols.returncode == 0 and "transform_string" in symbols.stdout, \
        "libtransform.so does not export transform_string."

    library = ctypes.CDLL(SO_PATH)
    transform = library.transform_string
    transform.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    transform.restype = None
    for value in ["Verifier-" + secrets.token_hex(8), "Mixed_Case_123!", "websocket test"]:
        output = ctypes.create_string_buffer(1024)
        transform(value.encode(), output)
        assert output.value.decode() == value[::-1] + "_processed"


def test_rust_server_built_and_serves_websockets():
    assert os.path.isfile(SERVER_PATH), f"Rust server executable {SERVER_PATH} does not exist."
    assert os.access(SERVER_PATH, os.X_OK), f"Rust server {SERVER_PATH} is not executable."
    assert_elf(SERVER_PATH, {2, 3})  # ET_EXEC or PIE ET_DYN

    before = sha256(SERVER_PATH)
    build = subprocess.run(["cargo", "build", "--offline"], cwd=RUST_DIR, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    assert build.returncode == 0, f"Cargo build failed:\n{build.stdout}"
    assert sha256(SERVER_PATH) == before, \
        "The existing server executable was not an up-to-date Cargo build artifact."

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = C_DIR + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    linked = subprocess.run(["ldd", SERVER_PATH], env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10)
    assert linked.returncode == 0, f"Could not inspect server linkage:\n{linked.stdout}"
    assert "libtransform.so" in linked.stdout and "not found" not in linked.stdout, \
        f"Rust server is not dynamically linked to the compiled C library:\n{linked.stdout}"

    subprocess.run(["pkill", "-x", "rust_server"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    time.sleep(0.3)
    server = subprocess.Popen([SERVER_PATH], cwd=RUST_DIR, env=env,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              start_new_session=True, text=True)

    async def exercise_server():
        values = [
            "OrganizeFiles",
            "probe-" + secrets.token_hex(10),
            "Dynamic_" + secrets.token_hex(6) + "_Input!",
        ]
        last_error = None
        for _ in range(30):
            if server.poll() is not None:
                output = server.stdout.read() if server.stdout else ""
                raise AssertionError(f"Rust server exited before accepting connections:\n{output}")
            try:
                async with websockets.connect("ws://127.0.0.1:9001", open_timeout=1) as ws:
                    await ws.send(values[0])
                    response = await asyncio.wait_for(ws.recv(), timeout=2)
                    assert response == values[0][::-1] + "_processed"
                break
            except (OSError, asyncio.TimeoutError):
                last_error = True
                await asyncio.sleep(0.1)
        else:
            raise AssertionError(f"Could not connect to the Rust WebSocket server: {last_error}")

        for value in values[1:]:
            async with websockets.connect("ws://127.0.0.1:9001", open_timeout=2) as ws:
                await ws.send(value)
                response = await asyncio.wait_for(ws.recv(), timeout=2)
                assert response == value[::-1] + "_processed", \
                    f"Server returned an incorrect transformation for {value!r}."

    try:
        asyncio.run(exercise_server())
    finally:
        if server.poll() is None:
            os.killpg(server.pid, signal.SIGTERM)
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(server.pid, signal.SIGKILL)
                server.wait(timeout=5)


def test_ws_response_file_content():
    assert os.path.isfile(RESPONSE_FILE), f"Response file {RESPONSE_FILE} does not exist."
    input_str = "OrganizeFiles"
    expected_response = input_str[::-1] + "_processed"
    with open(RESPONSE_FILE, "r") as f:
        actual_response = f.read().strip()
    assert actual_response == expected_response, \
        f"Expected '{expected_response}' but got '{actual_response}' in {RESPONSE_FILE}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
fi
