#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import ctypes
import json
import os
import random
import signal
import socket
import subprocess
import time

import pytest
import websockets

SERVER_BINARY = "/tmp/submission_graph_server"
SERVER = None


def kill_port_8080():
    target_inode = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if local.rsplit(":", 1)[-1].upper() == "1F90" and state == "0A":
                        target_inode.add(fields[9])
        except OSError:
            pass

    victims = set()
    if target_inode:
        for pid in os.listdir("/proc"):
            if not pid.isdigit() or int(pid) == os.getpid():
                continue
            fd_dir = f"/proc/{pid}/fd"
            try:
                for fd in os.listdir(fd_dir):
                    try:
                        link = os.readlink(os.path.join(fd_dir, fd))
                    except OSError:
                        continue
                    if link.startswith("socket:[") and link[8:-1] in target_inode:
                        victims.add(int(pid))
                        break
            except OSError:
                continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_server(proc):
    deadline = time.time() + 10
    while time.time() < deadline:
        if proc.poll() is not None:
            out, err = proc.communicate(timeout=1)
            pytest.fail(f"Go server exited before listening. stdout={out!r}, stderr={err!r}")
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail("Go server did not listen on 127.0.0.1:8080")


def start_server():
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = "/home/user/legacy_c" + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    proc = subprocess.Popen(
        [SERVER_BINARY], cwd="/home/user", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    wait_for_server(proc)
    return proc


def stop_server():
    global SERVER
    if SERVER is not None and SERVER.poll() is None:
        SERVER.terminate()
        try:
            SERVER.wait(timeout=3)
        except subprocess.TimeoutExpired:
            SERVER.kill()
            SERVER.wait(timeout=3)
    SERVER = None


def expected_reachable(target):
    lib = ctypes.CDLL("/home/user/legacy_c/libgraph.so")
    lib.get_children.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_int), ctypes.c_int]
    lib.get_children.restype = ctypes.c_int
    seen = set()
    pending = [target]
    while pending:
        node = pending.pop()
        if node in seen:
            continue
        seen.add(node)
        children = (ctypes.c_int * 100)()
        count = lib.get_children(node, children, 100)
        assert 0 <= count <= 100, f"Legacy library returned invalid child count {count}"
        pending.extend(children[i] for i in range(count) if children[i] not in seen)
    return sorted(seen)


@pytest.fixture(scope="module", autouse=True)
def built_server():
    global SERVER
    assert os.path.isfile("/home/user/server.go"), "Expected Go server file /home/user/server.go does not exist."
    assert os.path.isfile("/home/user/test_ws.py"), "Expected Python script /home/user/test_ws.py does not exist."

    env = os.environ.copy()
    env["CGO_ENABLED"] = "1"
    env["LD_LIBRARY_PATH"] = "/home/user/legacy_c" + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    build = subprocess.run(
        ["go", "build", "-o", SERVER_BINARY, "server.go"],
        cwd="/home/user", env=env, text=True, capture_output=True, timeout=180
    )
    assert build.returncode == 0, f"Go server failed to compile:\n{build.stdout}\n{build.stderr}"

    ldd = subprocess.run(["ldd", SERVER_BINARY], env=env, text=True, capture_output=True, timeout=20)
    assert ldd.returncode == 0, f"Could not inspect server linkage: {ldd.stderr}"
    assert "libgraph.so" in ldd.stdout, "Built server is not dynamically linked to the required legacy libgraph.so"

    nm = subprocess.run(["nm", "-D", SERVER_BINARY], text=True, capture_output=True, timeout=20)
    assert nm.returncode == 0, f"Could not inspect server symbols: {nm.stderr}"
    assert "get_children" in nm.stdout, "Built server does not reference the required C get_children function"

    kill_port_8080()
    SERVER = start_server()
    try:
        yield
    finally:
        stop_server()
        kill_port_8080()


def test_server_go_exists():
    path = "/home/user/server.go"
    assert os.path.isfile(path), f"Expected Go server file {path} does not exist."


def test_python_script_exists():
    path = "/home/user/test_ws.py"
    assert os.path.isfile(path), f"Expected Python script {path} does not exist."


def test_websocket_server_uses_legacy_graph():
    targets = list(range(1, 9))
    targets.extend(random.SystemRandom().sample(range(20, 10000), 3))

    async def exercise():
        async with websockets.connect("ws://127.0.0.1:8080/ws", open_timeout=5) as ws:
            for target in targets:
                await ws.send(json.dumps({"target": target}))
                raw = await asyncio.wait_for(ws.recv(), timeout=5)
                response = json.loads(raw)
                assert isinstance(response, dict), f"Response is not a JSON object: {response!r}"
                assert set(response) == {"reachable"}, f"Unexpected response shape: {response!r}"
                assert response["reachable"] == expected_reachable(target), (
                    f"Wrong reachable set for target {target}: {response['reachable']!r}"
                )
                assert response["reachable"] == sorted(set(response["reachable"])), (
                    "Reachable IDs must be unique and sorted ascending"
                )

    asyncio.run(exercise())


def test_python_runner_sends_target_and_writes_received_response():
    global SERVER
    stop_server()
    nonce = sorted(random.SystemRandom().sample(range(100000, 999999), 5))
    received = []
    try:
        os.remove("/home/user/migration_test.log")
    except FileNotFoundError:
        pass

    async def verify_client():
        async def handler(ws, *args):
            message = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
            received.append(message)
            await ws.send(json.dumps({"reachable": nonce}))

        async with websockets.serve(handler, "127.0.0.1", 8080):
            proc = await asyncio.create_subprocess_exec(
                "python3", "/home/user/test_ws.py",
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
            )
            try:
                stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=15)
            except asyncio.TimeoutError:
                proc.kill()
                await proc.wait()
                pytest.fail("Python test runner timed out")
            assert proc.returncode == 0, (
                f"Python test runner failed. stdout={stdout.decode(errors='replace')!r}, "
                f"stderr={stderr.decode(errors='replace')!r}"
            )

    asyncio.run(verify_client())
    assert received == [{"target": 2}], f"Python runner sent the wrong request: {received!r}"
    with open("/home/user/migration_test.log", "r") as f:
        assert f.read().strip() == ",".join(map(str, nonce)), (
            "Python runner did not write the reachable array received from the WebSocket server"
        )

    SERVER = start_server()
    os.remove("/home/user/migration_test.log")
    result = subprocess.run(
        ["python3", "/home/user/test_ws.py"], text=True, capture_output=True, timeout=20
    )
    assert result.returncode == 0, f"Python runner failed against Go server:\n{result.stdout}\n{result.stderr}"


def test_migration_test_log_contents():
    path = "/home/user/migration_test.log"
    assert os.path.isfile(path), f"Log file {path} does not exist. Did the Python script run successfully?"

    with open(path, "r") as f:
        content = f.read().strip()

    expected = "2,4,5,7,8"
    assert content == expected, f"Log file content is incorrect. Expected '{expected}', got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
