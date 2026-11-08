#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import secrets
import shutil
import socket
import subprocess
import sys
import tempfile
import time

APP = "/home/user/app"
LOG = "/home/user/test_result.log"


def stop_existing_servers():
    subprocess.run(["pkill", "-f", "/home/user/app/server.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.3)


def wait_for_file(path, proc, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.isfile(path):
            return
        if proc.poll() is not None:
            out, err = proc.communicate()
            raise AssertionError(f"Process exited before becoming ready. stdout={out!r}, stderr={err!r}")
        time.sleep(0.05)
    raise AssertionError(f"Timed out waiting for {path}")


def wait_for_port(proc, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            out, err = proc.communicate()
            raise AssertionError(f"Server exited during startup. stdout={out!r}, stderr={err!r}")
        try:
            with socket.create_connection(("127.0.0.1", 8765), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise AssertionError("Timed out waiting for the WebSocket server on port 8765")


def terminate(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)


def test_test_client_behavior_and_server_integration():
    client_path = os.path.join(APP, "test_client.py")
    assert os.path.isfile(client_path), f"The test client script {client_path} is missing."

    stop_existing_servers()
    token = "verifier-result-" + secrets.token_hex(24)
    work = tempfile.mkdtemp(prefix="ws_client_check_")
    ready = os.path.join(work, "ready")
    received = os.path.join(work, "received")
    mock_path = os.path.join(work, "mock_server.py")
    with open(mock_path, "w") as f:
        f.write(r'''import asyncio
import json
import sys
import websockets

ready, received, token = sys.argv[1:]

async def handler(ws, *args):
    raw = await ws.recv()
    with open(received, "w") as out:
        out.write(raw)
    try:
        data = json.loads(raw)
    except Exception:
        await ws.close()
        return
    if data != {"action": "reverse", "text": "Z" * 100}:
        await ws.close()
        return
    await ws.send(json.dumps({"status": "ok", "result": token}))

async def main():
    async with websockets.serve(handler, "localhost", 8765):
        with open(ready, "w") as out:
            out.write("ready")
        await asyncio.Future()

asyncio.run(main())
''')

    mock = subprocess.Popen(
        [sys.executable, mock_path, ready, received, token],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        wait_for_file(ready, mock)
        if os.path.exists(LOG):
            os.remove(LOG)
        run = subprocess.run(
            [sys.executable, client_path], cwd=APP,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
        )
        assert run.returncode == 0, f"test_client.py failed against a WebSocket server: {run.stderr}"
        assert os.path.isfile(received), "The client did not send a WebSocket message."
        with open(received) as f:
            sent = json.loads(f.read())
        assert sent == {"action": "reverse", "text": "Z" * 100}, "The client did not send the required JSON payload."
        assert os.path.isfile(LOG), "The client did not create /home/user/test_result.log."
        with open(LOG, "rb") as f:
            assert f.read() == token.encode(), "The client did not write only the response's result field."
    finally:
        terminate(mock)
        shutil.rmtree(work, ignore_errors=True)

    server = subprocess.Popen(
        [sys.executable, os.path.join(APP, "server.py")], cwd=APP,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    try:
        wait_for_port(server)
        if os.path.exists(LOG):
            os.remove(LOG)
        run = subprocess.run(
            [sys.executable, client_path], cwd=APP,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
        )
        assert run.returncode == 0, f"test_client.py failed against the project server: {run.stderr}"
        time.sleep(0.2)
        assert server.poll() is None, "The WebSocket server crashed after receiving the 100-character payload."
        assert os.path.isfile(LOG), "The integration run did not create /home/user/test_result.log."
        with open(LOG, "rb") as f:
            assert f.read() == (b"Z" * 100), "The integration run did not write only the transformed result."
    finally:
        terminate(server)


def test_test_result_log_content():
    log_path = "/home/user/test_result.log"
    assert os.path.isfile(log_path), f"Expected result log file {log_path} is missing."

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_content = "Z" * 100
    assert content == expected_content, f"Content of {log_path} is incorrect. Expected 100 'Z's, got {len(content)} characters."


def test_processor_c_fixed():
    c_path = "/home/user/app/processor.c"
    assert os.path.isfile(c_path), f"{c_path} is missing."

    with open(c_path, "r") as f:
        content = f.read()

    assert "char buffer[50];" not in content, "Vulnerable fixed-size buffer `char buffer[50];` is still present in processor.c."
    assert "strcpy(buffer, input_str);" not in content, "Unsafe `strcpy(buffer, input_str);` is still present in processor.c."

    has_dynamic_alloc = "malloc" in content or "strdup" in content or "calloc" in content or "PyMem_Malloc" in content
    assert has_dynamic_alloc, "processor.c does not seem to use dynamic memory allocation (e.g., malloc, strdup)."

    has_free = "free" in content or "PyMem_Free" in content
    assert has_free, "processor.c does not seem to free the dynamically allocated memory."

    code = re.sub(r"/\*.*?\*/|//[^\n]*", "", content, flags=re.S)
    assert re.search(r"\b(?:malloc|calloc|strdup|PyMem_Malloc)\s*\(", code), "No actual dynamic-allocation call was found in processor.c."
    assert re.search(r"\b(?:free|PyMem_Free)\s*\(", code), "No actual deallocation call was found in processor.c."


def exercise_extension(pythonpath):
    checker = r'''
import os
import random
import resource
import sys

resource.setrlimit(resource.RLIMIT_AS, (256 * 1024 * 1024, 256 * 1024 * 1024))
sys.path.insert(0, os.environ["EXT_PATH"])
import processor
assert os.path.realpath(processor.__file__).startswith(os.path.realpath(os.environ["EXT_PATH"]) + os.sep)

rng = random.Random(int.from_bytes(os.urandom(16), "big"))
lengths = [0, 1, 2, 49, 50, 51, 99, 100, 101, 1024, 65537, 200003]
for n in lengths:
    value = "".join(rng.choice("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789") for _ in range(n))
    assert processor.reverse(value) == value[::-1]

big = ("abcdefghijklmnopqrstuvwxyz012345" * 4096)
expected = big[::-1]
for _ in range(2200):
    result = processor.reverse(big)
    assert result == expected
'''
    env = os.environ.copy()
    env["EXT_PATH"] = pythonpath
    run = subprocess.run(
        [sys.executable, "-c", checker], cwd="/tmp", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=45
    )
    assert run.returncode == 0, f"Compiled processor failed randomized, long-input, or leak-stress checks: {run.stderr}"


def test_extension_compiled():
    so_files = glob.glob("/home/user/app/processor.*.so")
    assert len(so_files) > 0, "The C extension was not compiled in-place in /home/user/app. Missing processor.*.so file."
    assert any(os.path.isfile(path) for path in so_files), "The in-place processor extension is not a regular file."
    c_mtime = os.stat(os.path.join(APP, "processor.c")).st_mtime_ns
    assert any(os.stat(path).st_mtime_ns >= c_mtime for path in so_files), "The in-place extension is older than processor.c; rebuild it after applying the fix."
    exercise_extension(APP)


def test_submitted_source_builds_and_is_safe():
    work = tempfile.mkdtemp(prefix="processor_source_build_")
    try:
        lib = os.path.join(work, "lib")
        temp = os.path.join(work, "temp")
        run = subprocess.run(
            [sys.executable, "setup.py", "build_ext", "--force", "--build-lib", lib, "--build-temp", temp],
            cwd=APP, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
        )
        assert run.returncode == 0, f"The submitted processor.c does not compile: {run.stderr}"
        assert glob.glob(os.path.join(lib, "processor*.so")), "Building the submitted source produced no processor extension."
        exercise_extension(lib)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def test_test_client_script_exists():
    client_path = "/home/user/app/test_client.py"
    assert os.path.isfile(client_path), f"The test client script {client_path} is missing."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
