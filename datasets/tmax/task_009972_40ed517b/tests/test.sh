#!/bin/bash
set -e
mkdir -p /logs/verifier
export PATH="/opt/rust/bin:${PATH}"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import ctypes
import json
import os
import secrets
import socket
import subprocess
import sys
import tempfile
import time

import websockets

BASE = "/home/user/math_integration"
ENGINE = os.path.join(BASE, "rust_engine")
SO_PATH = os.path.join(ENGINE, "target/debug/librust_engine.so")
SERVER = os.path.join(BASE, "server.py")
CLIENT = os.path.join(BASE, "test_client.py")
RESULT = "/home/user/result.txt"


def compute_expected_sequence(n: int) -> int:
    seq = [1, 1]
    for i in range(2, n + 1):
        seq.append(seq[i - 1] + 2 * seq[i - 2])
    return seq[n]


def port_open(port=8765):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.3):
            return True
    except OSError:
        return False


def wait_for_port(proc, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            raise AssertionError("server.py exited before accepting connections")
        if port_open():
            return
        time.sleep(0.1)
    raise AssertionError("server.py did not start listening on port 8765")


def stop_existing_server():
    subprocess.run(["pkill", "-f", "[s]erver.py"], check=False)
    deadline = time.time() + 5
    while time.time() < deadline and port_open():
        time.sleep(0.1)
    assert not port_open(), "Could not stop the existing server on port 8765"


def test_rust_engine_compiled():
    # Preserve the original existence assertion.
    assert os.path.exists(SO_PATH), (
        f"Compiled Rust library not found at {SO_PATH}. Did you run 'cargo build'?"
    )

    # Force compilation from the submitted Rust source rather than trusting a file
    # placed at the expected output path.
    subprocess.run(["cargo", "clean"], cwd=ENGINE, check=True, timeout=60)
    subprocess.run(["cargo", "build"], cwd=ENGINE, check=True, timeout=120)
    assert os.path.isfile(SO_PATH), "cargo build did not produce librust_engine.so"

    lib = ctypes.CDLL(SO_PATH)
    fn = lib.compute_sequence
    fn.argtypes = [ctypes.c_uint32]
    fn.restype = ctypes.c_uint64
    samples = {0, 1, 2, 3, 10, secrets.SystemRandom().randint(11, 35)}
    for n in samples:
        assert fn(n) == compute_expected_sequence(n), (
            f"Rust compute_sequence returned the wrong value for n={n}"
        )


def test_server_py_fixed():
    # Preserve the original source check.
    assert os.path.exists(SERVER), f"Missing server.py at {SERVER}"
    with open(SERVER, "r") as f:
        content = f.read()
    assert '< "2.1.0"' not in content, (
        "server.py still contains the naive string comparison bug for the version."
    )


def test_server_was_started_by_agent():
    assert port_open(), (
        "No server was listening on localhost:8765; start server.py in the background"
    )


def test_client_uses_websocket_and_required_payload():
    stop_existing_server()
    nonce = secrets.SystemRandom().randint(10**11, 10**12 - 1)

    with tempfile.TemporaryDirectory() as td:
        captured = os.path.join(td, "captured.json")
        ready = os.path.join(td, "ready")
        mock = os.path.join(td, "mock_server.py")
        with open(mock, "w") as f:
            f.write(r'''import asyncio
import json
import sys
import websockets

captured, ready, nonce = sys.argv[1], sys.argv[2], int(sys.argv[3])
done = asyncio.Event()

async def handler(ws, *args):
    message = await ws.recv()
    with open(captured, "w") as out:
        out.write(message)
    await ws.send(json.dumps({"result": nonce}))
    done.set()

async def main():
    async with websockets.serve(handler, "localhost", 8765):
        with open(ready, "w") as out:
            out.write("ready")
        await done.wait()

asyncio.run(main())
''')
        proc = subprocess.Popen(
            [sys.executable, mock, captured, ready, str(nonce)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            deadline = time.time() + 10
            while not os.path.exists(ready) and time.time() < deadline:
                assert proc.poll() is None, "Mock WebSocket server exited unexpectedly"
                time.sleep(0.05)
            assert os.path.exists(ready), "Mock WebSocket server failed to start"

            if os.path.exists(RESULT):
                os.remove(RESULT)
            subprocess.run(
                [sys.executable, CLIENT], cwd=BASE, check=True, timeout=20
            )
            proc.wait(timeout=5)

            with open(captured, "r") as f:
                payload = json.load(f)
            assert payload == {"version": "10.0.0", "n": 20}, (
                "test_client.py did not send the required JSON payload"
            )
            with open(RESULT, "r") as f:
                raw = f.read()
            assert raw == str(nonce), (
                "test_client.py did not write only the integer returned by the server"
            )
        finally:
            if proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=5)


def test_live_server_semver_ffi_and_final_result():
    assert not port_open(), "Port 8765 is unexpectedly still occupied"
    server_proc = subprocess.Popen(
        [sys.executable, SERVER],
        cwd=BASE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    wait_for_port(server_proc)

    async def exercise_server():
        uri = "ws://localhost:8765"
        cases = [
            ("2.1.0", secrets.SystemRandom().randint(4, 12), True),
            ("10.0.0", secrets.SystemRandom().randint(13, 35), True),
            ("2.10.0", secrets.SystemRandom().randint(4, 20), True),
            ("2.0.9", 8, False),
        ]
        for version, n, accepted in cases:
            async with websockets.connect(uri) as ws:
                await ws.send(json.dumps({"version": version, "n": n}))
                response = json.loads(await ws.recv())
            if accepted:
                assert response.get("result") == compute_expected_sequence(n), (
                    f"Server returned an incorrect FFI result for version={version}, n={n}"
                )
                assert "error" not in response
            else:
                assert "error" in response, (
                    "Server accepted protocol version 2.0.9, which is below 2.1.0"
                )

    asyncio.run(exercise_server())

    if os.path.exists(RESULT):
        os.remove(RESULT)
    subprocess.run([sys.executable, CLIENT], cwd=BASE, check=True, timeout=20)

    # Preserve the original final-result assertions, and additionally enforce
    # that the file contains only the integer with no surrounding text.
    assert os.path.exists(RESULT), (
        f"Result file not found at {RESULT}. Did the client script run successfully?"
    )
    with open(RESULT, "r") as f:
        raw = f.read()
    content = raw.strip()
    expected_result = str(compute_expected_sequence(20))
    assert content == expected_result, (
        f"Result file contains '{content}', but expected '{expected_result}'."
    )
    assert raw == expected_result, "result.txt must contain only the final integer"

    # Deliberately leave the successfully relaunched server running in the background.
    assert server_proc.poll() is None
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
