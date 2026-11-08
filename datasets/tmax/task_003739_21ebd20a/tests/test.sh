#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path

BASE = Path("/home/user/ci_task")

EXPECTED_SERVER = b'''import asyncio
import websockets
import sys

async def handler(websocket):
    with open(sys.argv[1], 'r') as f:
        data = f.read()
    await websocket.send(data)

async def main():
    async with websockets.serve(handler, "localhost", 8765):
        await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())
'''

EXPECTED_PBT = b'''import asyncio
import websockets
import json
import sys
from hypothesis import given, strategies as st

async def fetch_data():
    try:
        async with websockets.connect("ws://localhost:8765") as ws:
            data = await ws.recv()
            return data
    except Exception as e:
        print(f"Failed to connect to WebSocket: {e}")
        sys.exit(1)

data_str = asyncio.run(fetch_data())
try:
    payloads = json.loads(data_str)
except json.JSONDecodeError:
    print("Invalid JSON structure received.")
    sys.exit(1)

# Property-based testing logic
def verify_properties(data):
    for item in data:
        assert "<" not in item['input'], "Unsanitized '<' found!"
        assert ">" not in item['input'], "Unsanitized '>' found!"
        assert "alert" not in item['input'], "Unsanitized 'alert' found!"

try:
    verify_properties(payloads)
    with open("/home/user/ci_task/success.txt", "w") as f:
        f.write("PBT_PASSED")
    print("All properties passed! Artifact created.")
except AssertionError as e:
    print(f"Property test failed: {e}")
    sys.exit(1)
'''


def expected_sanitization(data):
    return data.replace(b"<", b"&lt;").replace(b">", b"&gt;").replace(b"a", b"b")


def run_sanitizer(data):
    result = subprocess.run(
        [str(BASE / "ws_sanitizer")],
        input=data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=BASE,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    return result.stdout


def stop_existing_task_servers():
    me = os.getpid()
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit() or int(entry.name) == me:
            continue
        try:
            cmdline = (entry / "cmdline").read_bytes()
            if b"ws_server.py" in cmdline:
                os.kill(int(entry.name), signal.SIGTERM)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    time.sleep(0.3)


def test_00_pipeline_was_built_and_executes_authentically():
    assert (BASE / "ws_server.py").read_bytes() == EXPECTED_SERVER, "ws_server.py was modified."
    assert (BASE / "pbt_test.py").read_bytes() == EXPECTED_PBT, "pbt_test.py was modified."

    executable = BASE / "ws_sanitizer"
    if executable.exists() or executable.is_symlink():
        executable.unlink()
    build = subprocess.run(
        ["make"], cwd=BASE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert build.returncode == 0, build.stderr.decode(errors="replace")
    assert executable.is_file(), "make did not build ws_sanitizer."
    assert os.access(executable, os.X_OK), "The built ws_sanitizer is not executable."
    assert executable.read_bytes()[:4] == b"\x7fELF", "ws_sanitizer is not a compiled native executable."

    raw = (BASE / "raw_payloads.json").read_bytes()
    expected = expected_sanitization(raw)
    assert run_sanitizer(raw) == expected, "ws_sanitizer did not perform the required transformation."
    assert (BASE / "sanitized.json").read_bytes() == expected, "sanitized.json was not produced from raw_payloads.json by the required sanitizer."

    probes = [
        b'<alert>normal data</alert>',
        json.dumps([{"id": i, "input": text} for i, text in enumerate([
            "safe", "<script>alert(1)</script>", "banana", ">a<", "onerror=alert(2)"
        ])]).encode(),
        os.urandom(64).hex().encode() + b"<a>alert>alpha",
    ]
    for probe in probes:
        assert run_sanitizer(probe) == expected_sanitization(probe)

    assert (BASE / "ws_server.py").read_bytes() == EXPECTED_SERVER
    assert (BASE / "pbt_test.py").read_bytes() == EXPECTED_PBT

    success = BASE / "success.txt"
    if success.exists() or success.is_symlink():
        success.unlink()
    stop_existing_task_servers()
    server = subprocess.Popen(
        [sys.executable, str(BASE / "ws_server.py"), "sanitized.json"],
        cwd=BASE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        deadline = time.time() + 10
        while time.time() < deadline:
            assert server.poll() is None, "The WebSocket server exited before accepting connections."
            try:
                with socket.create_connection(("127.0.0.1", 8765), timeout=0.2):
                    break
            except OSError:
                time.sleep(0.1)
        else:
            raise AssertionError("The WebSocket server did not start on port 8765.")

        pbt = subprocess.run(
            [sys.executable, str(BASE / "pbt_test.py")],
            cwd=BASE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert pbt.returncode == 0, (pbt.stdout + pbt.stderr).decode(errors="replace")
    finally:
        if server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=5)

    assert success.is_file(), "The PBT script did not generate success.txt."
    assert success.read_text().strip() == "PBT_PASSED"


def test_success_txt_exists():
    path = "/home/user/ci_task/success.txt"
    assert os.path.isfile(path), f"The file {path} does not exist. Did the PBT script run successfully?"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "PBT_PASSED", f"Expected {path} to contain 'PBT_PASSED', but got '{content}'."


def test_ws_sanitizer_built():
    path = "/home/user/ci_task/ws_sanitizer"
    assert os.path.isfile(path), f"The executable {path} does not exist. Did you fix the Makefile and run make?"
    assert os.access(path, os.X_OK), f"The file {path} is not executable."


def test_sanitized_json_exists_and_valid():
    path = "/home/user/ci_task/sanitized.json"
    assert os.path.isfile(path), f"The file {path} does not exist. Did you pipe the output to sanitized.json?"
    try:
        with open(path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        assert False, f"The file {path} does not contain valid JSON."
    assert isinstance(data, list), f"Expected JSON array in {path}."
    for item in data:
        assert "input" in item, f"Missing 'input' key in {path}."
        assert "<" not in item["input"], "Unsanitized '<' found in sanitized.json!"
        assert ">" not in item["input"], "Unsanitized '>' found in sanitized.json!"
        assert "alert" not in item["input"], "Unsanitized 'alert' found in sanitized.json!"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
