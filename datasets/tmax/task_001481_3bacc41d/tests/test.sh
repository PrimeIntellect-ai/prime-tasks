#!/bin/bash
set -e
mkdir -p /logs/verifier

# Make the legacy executable unavailable while submitted code is exercised.
# The agent needed it for reverse engineering, but the finished server must not call it.
LEGACY_MODE="$(stat -c '%a' /app/legacy_emu 2>/dev/null || echo 755)"
chown root:root /app/legacy_emu 2>/dev/null || true
chmod 000 /app/legacy_emu
restore_legacy() {
    chmod "$LEGACY_MODE" /app/legacy_emu 2>/dev/null || chmod 755 /app/legacy_emu 2>/dev/null || true
}
trap restore_legacy EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import asyncio
import glob
import json
import os
import pwd
import random
import re
import subprocess
import time
import uuid

import pytest
import websockets

MASK64 = (1 << 64) - 1
SIGN64 = 1 << 63


def signed64(value):
    value &= MASK64
    return value - (1 << 64) if value & SIGN64 else value


def c_atoll(text):
    match = re.match(r"^[+-]?\d+", text)
    if not match:
        return 0
    value = int(match.group(0))
    if value > (1 << 63) - 1:
        return (1 << 63) - 1
    if value < -(1 << 63):
        return -(1 << 63)
    return value


def emulate_truth(code: str) -> str:
    stack = []
    output = []
    for token in code.split():
        if token.startswith("P"):
            stack.append(c_atoll(token[1:]))
        elif token == "A":
            if len(stack) < 2:
                output.append("ERR")
                break
            b = stack.pop()
            a = stack.pop()
            stack.append(signed64(a + b))
        elif token == "S":
            if len(stack) < 2:
                output.append("ERR")
                break
            b = stack.pop()
            a = stack.pop()
            stack.append(signed64(a - b))
        elif token == "M":
            if len(stack) < 2:
                output.append("ERR")
                break
            b = stack.pop()
            a = stack.pop()
            stack.append(signed64(a * b))
        elif token == "O":
            if not stack:
                output.append("ERR")
                break
            output.append(str(stack.pop()))

    return "" if not output else "\n".join(output) + "\n"


def generate_random_program() -> str:
    tokens = []
    stack_size = 0
    for _ in range(random.randint(5, 50)):
        op = random.choice(["P", "A", "S", "M", "O", "ERR"])
        if op == "P" or stack_size < 2:
            tokens.append(f"P{random.randint(-100, 100)}")
            stack_size += 1
        elif op in ("A", "S", "M"):
            tokens.append(op)
            stack_size -= 1
        elif op == "O":
            tokens.append("O")
            stack_size -= 1
        else:
            tokens.append(random.choice(["A", "S", "M", "O"]))
            stack_size -= 2
    return " ".join(tokens)


def demote_to_user():
    account = pwd.getpwnam("user")
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


async def wait_for_server(proc, timeout=6):
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            out, err = proc.communicate(timeout=1)
            raise AssertionError(
                f"server exited before listening; stdout={out!r}, stderr={err!r}"
            )
        try:
            ws = await websockets.connect("ws://localhost:8765")
            await ws.close()
            return
        except Exception as exc:
            last_error = exc
            await asyncio.sleep(0.05)
    raise AssertionError(f"server did not listen on localhost:8765: {last_error}")


def stop_process(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)


@pytest.fixture
async def running_server():
    server_path = "/home/user/server.py"
    assert os.path.isfile(server_path), f"Server script {server_path} not found."
    proc = subprocess.Popen(
        ["python3", server_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        preexec_fn=demote_to_user,
    )
    try:
        await wait_for_server(proc)
        yield proc
    finally:
        stop_process(proc)


def test_server_is_pure_python_and_does_not_launch_legacy():
    server_path = "/home/user/server.py"
    assert os.path.isfile(server_path), f"Server script {server_path} not found."

    # Check the server and local Python helper modules, excluding the required e2e
    # orchestrator, which is expected to launch server.py.
    paths = [
        p for p in glob.glob("/home/user/**/*.py", recursive=True)
        if os.path.realpath(p) != "/home/user/e2e_test.py"
    ]
    assert server_path in paths
    for path in paths:
        source = open(path, "r", encoding="utf-8").read()
        tree = ast.parse(source, filename=path)
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                assert all(alias.name != "subprocess" for alias in node.names), (
                    f"{path} imports subprocess; the server must emulate natively"
                )
                assert all(alias.name != "ctypes" for alias in node.names), (
                    f"{path} loads native code through ctypes"
                )
            if isinstance(node, ast.ImportFrom):
                assert node.module not in ("subprocess", "ctypes"), (
                    f"{path} imports process/native-code helpers"
                )
            if isinstance(node, ast.Call):
                name = ""
                if isinstance(node.func, ast.Name):
                    name = node.func.id
                elif isinstance(node.func, ast.Attribute):
                    name = node.func.attr
                assert name not in {
                    "system", "popen", "Popen", "create_subprocess_exec",
                    "create_subprocess_shell", "fork", "forkpty"
                }, f"{path} contains a process-launch call ({name})"


@pytest.mark.asyncio
async def test_emulator_accuracy(running_server):
    random.seed(20260911)
    correct_outputs = 0
    total_programs = 1000

    async with websockets.connect("ws://localhost:8765") as websocket:
        for i in range(total_programs):
            code = generate_random_program()
            expected_output = emulate_truth(code)
            payload = json.dumps({"client_id": f"test_client_{i}", "code": code})
            await websocket.send(payload)
            response_str = await asyncio.wait_for(websocket.recv(), timeout=2)
            try:
                response = json.loads(response_str)
            except json.JSONDecodeError:
                response = {}
            if response.get("result", "") == expected_output:
                correct_outputs += 1

    accuracy = correct_outputs / total_programs
    assert accuracy >= 1.0, (
        f"Accuracy {accuracy} is below 1.0: {correct_outputs}/{total_programs}"
    )


@pytest.mark.asyncio
async def test_overflow_underflow_and_invalid_tokens(running_server):
    cases = [
        "P9223372036854775807 P1 A O",
        "P-9223372036854775808 P1 S O",
        "P4294967296 P4294967296 M O",
        "P-9223372036854775808 P-1 M O",
        "A P99 O",
        "P7 O O P8 O",
        "Pxyz O",
        "P12junk O",
        "ignored P4 ignored P5 A O",
        "P1\nP2\nA\nO",
    ]
    async with websockets.connect("ws://localhost:8765") as websocket:
        for index, code in enumerate(cases):
            await websocket.send(json.dumps({
                "client_id": f"edge-{index}-{uuid.uuid4().hex}",
                "code": code,
            }))
            response = json.loads(await asyncio.wait_for(websocket.recv(), timeout=2))
            assert response == {"result": emulate_truth(code)}, (code, response)


@pytest.mark.asyncio
async def test_request_validation(running_server):
    malformed_messages = [
        "not json",
        "null",
        "[]",
        "{}",
        json.dumps({"client_id": "missing-code"}),
        json.dumps({"code": "P1 O"}),
        json.dumps({"client_id": 123, "code": "P1 O"}),
        json.dumps({"client_id": "x", "code": 123}),
        json.dumps({"client_id": None, "code": "P1 O"}),
    ]
    async with websockets.connect("ws://localhost:8765") as websocket:
        for message in malformed_messages:
            await websocket.send(message)
            raw = await asyncio.wait_for(websocket.recv(), timeout=2)
            assert json.loads(raw) == {"error": "invalid request"}, (message, raw)


@pytest.mark.asyncio
async def test_rate_limit_is_per_client_id_across_connections(running_server):
    client_id = "rate-" + uuid.uuid4().hex
    payload = json.dumps({"client_id": client_id, "code": "P1 O"})

    async with websockets.connect("ws://localhost:8765") as websocket:
        for _ in range(3):
            await websocket.send(payload)
            assert json.loads(await asyncio.wait_for(websocket.recv(), timeout=2)) == {
                "result": "1\n"
            }

    # Reconnect to ensure limiting is keyed by client_id, not by connection.
    async with websockets.connect("ws://localhost:8765") as websocket:
        for _ in range(2):
            await websocket.send(payload)
            assert json.loads(await asyncio.wait_for(websocket.recv(), timeout=2)) == {
                "result": "1\n"
            }
        await websocket.send(payload)
        assert json.loads(await asyncio.wait_for(websocket.recv(), timeout=2)) == {
            "error": "rate limited"
        }

        await asyncio.sleep(1.1)
        await websocket.send(payload)
        assert json.loads(await asyncio.wait_for(websocket.recv(), timeout=2)) == {
            "result": "1\n"
        }


def test_e2e_script_exists_and_has_required_orchestration():
    path = "/home/user/e2e_test.py"
    assert os.path.isfile(path), f"End-to-end test script {path} not found."
    source = open(path, "r", encoding="utf-8").read()
    tree = ast.parse(source, filename=path)
    constants = "\n".join(
        node.value for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, str)
    )
    call_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                call_names.add(node.func.id)
            elif isinstance(node.func, ast.Attribute):
                call_names.add(node.func.attr)

    assert "/home/user/server.py" in constants
    assert "ALL TESTS PASSED" in constants
    assert "rate limited" in constants
    assert all(piece in constants for piece in ("P10", "P5", "P2")), (
        "e2e_test.py must send the requested (10 + 5) * 2 program"
    )
    assert {"Popen", "create_subprocess_exec", "create_subprocess_shell"} & call_names, (
        "e2e_test.py must start server.py as a background process"
    )
    assert "connect" in call_names and "send" in call_names and "recv" in call_names
    assert {"terminate", "kill"} & call_names, "e2e_test.py must clean up its server"
    assert sum(isinstance(node, ast.Assert) for node in ast.walk(tree)) >= 2, (
        "e2e_test.py must assert both emulator and rate-limit behavior"
    )


def test_e2e_script_runs_and_cleans_up():
    path = "/home/user/e2e_test.py"
    completed = subprocess.run(
        ["python3", path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        preexec_fn=demote_to_user,
    )
    assert completed.returncode == 0, (
        f"e2e_test.py failed: stdout={completed.stdout!r}, stderr={completed.stderr!r}"
    )
    assert "ALL TESTS PASSED" in completed.stdout.splitlines()

    async def ensure_no_server_remains():
        await asyncio.sleep(0.2)
        with pytest.raises(Exception):
            await asyncio.wait_for(
                websockets.connect("ws://localhost:8765"), timeout=1
            )

    asyncio.run(ensure_no_server_remains())
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
