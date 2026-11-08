#!/bin/bash
set -e
mkdir -p /logs/verifier

# Ensure verification starts its own instance of the submitted server.
pkill -f '[s]erver.py' 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import asyncio
import ctypes
import os
import random
import shutil
import subprocess
import tempfile
import time

import pytest
import websockets

HOME = "/home/user"


def test_client_patched():
    path = "/home/user/client.py"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert 'print("Running client...")' in content, f"{path} was not patched correctly (missing Python 3 print statement)."
    assert 'print "Running client..."' not in content, f"{path} still contains Python 2 print statement."


def test_evaluator_so_exists():
    path = "/home/user/evaluator.so"
    assert os.path.isfile(path), f"Shared library {path} was not created."


def test_server_py_exists():
    path = "/home/user/server.py"
    assert os.path.isfile(path), f"Server script {path} was not created."


def make_cases():
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))

    def expression(depth):
        if depth <= 0:
            value = rng.randint(1, 9)
            return str(value), value
        op = rng.choice(["+", "-", "*", "/"])
        left, left_value = expression(depth - 1)
        right, right_value = expression(depth - 1)
        if op == "/":
            # Construct an exact division so expected behavior is independent
            # of Python-versus-C rounding rules.
            divisor = rng.randint(1, 9)
            return f"/ * {left} {divisor} {divisor}", left_value
        if op == "+":
            return f"+ {left} {right}", left_value + right_value
        if op == "-":
            return f"- {left} {right}", left_value - right_value
        return f"* {left} {right}", left_value * right_value

    cases = [
        ("+ -7 12", 5),
        ("- 3 10", -7),
        ("* -4 6", -24),
        ("/ -21 3", -7),
        ("+ 3 * 4 5", 23),
    ]
    cases.extend(expression(rng.randint(1, 3)) for _ in range(20))
    return cases


CASES = make_cases()


def load_and_check_library(path):
    lib = ctypes.CDLL(path)
    function = lib.evaluate_prefix
    function.argtypes = [ctypes.c_char_p]
    function.restype = ctypes.c_int
    for expression, expected in CASES:
        actual = function(expression.encode("utf-8"))
        assert actual == expected, (
            f"evaluate_prefix({expression!r}) returned {actual}, expected {expected}"
        )


def test_c_evaluator_implementation_and_shared_library():
    source = os.path.join(HOME, "evaluator.c")
    library = os.path.join(HOME, "evaluator.so")
    assert os.path.isfile(source), f"C source file {source} was not created."

    # Exercise the submitted shared object itself, including its exported symbol.
    load_and_check_library(library)

    # Independently compile and exercise evaluator.c so a valid-looking shared
    # object cannot substitute for the requested C implementation.
    with tempfile.TemporaryDirectory() as directory:
        rebuilt = os.path.join(directory, "evaluator.so")
        result = subprocess.run(
            ["gcc", "-shared", "-o", rebuilt, "-fPIC", source],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, f"evaluator.c did not compile:\n{result.stderr}"
        load_and_check_library(rebuilt)


async def wait_for_server(process):
    last_error = None
    for _ in range(60):
        if process.poll() is not None:
            pytest.fail(f"server.py exited before accepting connections (status {process.returncode})")
        try:
            async with websockets.connect("ws://localhost:8080", open_timeout=0.5):
                return
        except Exception as error:
            last_error = error
            await asyncio.sleep(0.1)
    pytest.fail(f"server.py did not listen on ws://localhost:8080: {last_error}")


async def exchange(messages):
    replies = []
    async with websockets.connect("ws://localhost:8080", open_timeout=2) as websocket:
        for message in messages:
            await websocket.send(message)
            replies.append(await asyncio.wait_for(websocket.recv(), timeout=2))
    return replies


def start_server():
    process = subprocess.Popen(
        ["python3", os.path.join(HOME, "server.py")],
        cwd=HOME,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    asyncio.run(wait_for_server(process))
    return process


def stop_server(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)
    time.sleep(0.2)


def test_server_uses_ctypes_evaluator_and_pipeline_runs():
    server_path = os.path.join(HOME, "server.py")
    with open(server_path, "r") as file:
        server_source = file.read()
    tree = ast.parse(server_source, filename=server_path)
    imports_ctypes = any(
        (isinstance(node, ast.Import) and any(alias.name == "ctypes" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "ctypes")
        for node in ast.walk(tree)
    )
    assert imports_ctypes, "server.py must use the ctypes module."
    assert "evaluator.so" in server_source, "server.py does not load evaluator.so."

    library = os.path.join(HOME, "evaluator.so")
    backup = os.path.join(HOME, ".evaluator.so.verifier-backup")
    probe_source = os.path.join(HOME, ".evaluator_probe.c")
    probe_library = os.path.join(HOME, ".evaluator_probe.so")
    marker = 424242

    with open(probe_source, "w") as file:
        file.write(f"int evaluate_prefix(const char *expr) {{ (void)expr; return {marker}; }}\n")
    compiled = subprocess.run(
        ["gcc", "-shared", "-o", probe_library, "-fPIC", probe_source],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert compiled.returncode == 0, compiled.stderr

    process = None
    os.replace(library, backup)
    try:
        shutil.copy2(probe_library, library)
        process = start_server()
        replies = asyncio.run(exchange(["+ 100 200"]))
        assert replies == [str(marker)], (
            "server.py did not obtain its response from evaluate_prefix in evaluator.so"
        )
    finally:
        if process is not None:
            stop_server(process)
        if os.path.exists(backup):
            os.replace(backup, library)
        for path in (probe_source, probe_library):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

    # Exercise the restored submitted evaluator through the submitted WebSocket
    # server on verifier-derived inputs, then force the submitted client to
    # regenerate output.txt from the provided equations.
    process = start_server()
    try:
        replies = asyncio.run(exchange([expression for expression, _ in CASES]))
        expected = [str(value) for _, value in CASES]
        assert replies == expected, f"WebSocket evaluator returned {replies}, expected {expected}"

        output = os.path.join(HOME, "output.txt")
        try:
            os.remove(output)
        except FileNotFoundError:
            pass
        client = subprocess.run(
            ["python3", os.path.join(HOME, "client.py")],
            cwd=HOME,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert client.returncode == 0, f"client.py failed:\n{client.stdout}\n{client.stderr}"
        assert os.path.isfile(output), "client.py did not recreate /home/user/output.txt"
    finally:
        stop_server(process)


def test_output_correct():
    path = "/home/user/output.txt"
    assert os.path.isfile(path), f"Output file {path} was not created."

    expected_results = ["8", "20", "15", "10", "26"]

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected_results, f"Contents of {path} do not match the expected results. Got {lines}, expected {expected_results}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
