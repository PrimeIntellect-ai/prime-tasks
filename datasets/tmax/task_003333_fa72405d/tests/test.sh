#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import secrets
import subprocess
import sys

import pytest

BUILD_ENV_DIR = "/home/user/build_env"
MAKEFILE = os.path.join(BUILD_ENV_DIR, "Makefile")
ALGO_SOURCE = os.path.join(BUILD_ENV_DIR, "algo.c")
COLLATZ_EXEC = os.path.join(BUILD_ENV_DIR, "collatz")
WS_HANDLER = os.path.join(BUILD_ENV_DIR, "ws_handler.py")
WS_PAYLOAD = os.path.join(BUILD_ENV_DIR, "ws_payload.json")


def collatz_length(n):
    steps = 0
    while n > 1:
        if n % 2 == 0:
            n = n // 2
        else:
            n = 3 * n + 1
        steps += 1
    return steps


def run_make():
    return subprocess.run(
        ["make"], cwd=BUILD_ENV_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )


def test_makefile_builds_algo_c_and_binary_runs():
    assert os.path.isfile(MAKEFILE), f"Makefile not found at {MAKEFILE}"
    assert os.path.getsize(MAKEFILE) > 0, "Makefile is empty"
    assert os.path.isfile(ALGO_SOURCE), f"C source not found at {ALGO_SOURCE}"

    with open(ALGO_SOURCE, "rb") as f:
        original_source = f.read()

    old_literal = b'printf("Collatz length for 10 is %lld\\n", collatz_length(10));'
    assert old_literal in original_source, "algo.c no longer contains the supplied Collatz program"

    marker = ("VERIFIER_" + secrets.token_hex(12)).encode("ascii")
    replacement = b'printf("' + marker + b':%lld\\n", collatz_length(10));'

    try:
        with open(ALGO_SOURCE, "wb") as f:
            f.write(original_source.replace(old_literal, replacement, 1))
        if os.path.lexists(COLLATZ_EXEC):
            os.remove(COLLATZ_EXEC)

        result = run_make()
        assert result.returncode == 0, f"make failed:\n{result.stdout}"
        assert os.path.isfile(COLLATZ_EXEC), f"Executable not found at {COLLATZ_EXEC}"
        assert os.access(COLLATZ_EXEC, os.X_OK), f"File at {COLLATZ_EXEC} is not executable"

        with open(COLLATZ_EXEC, "rb") as f:
            assert f.read(4) == b"\x7fELF", "collatz is not a compiled ELF executable"

        nm_result = subprocess.run(
            ["nm", COLLATZ_EXEC], text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=10
        )
        assert nm_result.returncode == 0, "collatz is not inspectable as a compiled program"
        assert "collatz_length" in nm_result.stdout, "collatz does not contain collatz_length from algo.c"

        execution = subprocess.run(
            [COLLATZ_EXEC], text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=10
        )
        assert execution.returncode == 0, f"collatz exited with {execution.returncode}"
        assert execution.stdout == marker.decode("ascii") + ":6\n", \
            "The executable was not rebuilt from the current algo.c or computed the wrong result"
    finally:
        with open(ALGO_SOURCE, "wb") as f:
            f.write(original_source)
        if os.path.lexists(COLLATZ_EXEC):
            os.remove(COLLATZ_EXEC)
        run_make()

    assert os.path.isfile(COLLATZ_EXEC), f"Executable not found at {COLLATZ_EXEC}"
    final_run = subprocess.run(
        [COLLATZ_EXEC], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10
    )
    assert final_run.returncode == 0
    assert final_run.stdout == "Collatz length for 10 is 6\n"


def test_executable_exists():
    """Check if the collatz executable was built and is executable."""
    assert os.path.isfile(COLLATZ_EXEC), f"Executable not found at {COLLATZ_EXEC}"
    assert os.access(COLLATZ_EXEC, os.X_OK), f"File at {COLLATZ_EXEC} is not executable"


def test_python_script_exists():
    """Check if the ws_handler.py script exists."""
    assert os.path.isfile(WS_HANDLER), f"Python script not found at {WS_HANDLER}"


def test_python_script_executes_and_translates_algorithm():
    if os.path.lexists(WS_PAYLOAD):
        os.remove(WS_PAYLOAD)

    execution = subprocess.run(
        [sys.executable, WS_HANDLER], cwd=BUILD_ENV_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert execution.returncode == 0, \
        f"ws_handler.py failed:\n{execution.stdout}\n{execution.stderr}"
    assert os.path.isfile(WS_PAYLOAD), \
        "Running ws_handler.py did not generate ws_payload.json"

    with open(WS_HANDLER, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), WS_HANDLER)
    function_names = [
        node.name for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
    ]
    assert function_names, "ws_handler.py does not define a Python function"

    random_inputs = [secrets.randbelow(2_000_000) + 2 for _ in range(12)]
    inputs = [1, 2, 3, 10, 27, 837799] + random_inputs
    expected = [collatz_length(n) for n in inputs]

    checker = r'''
import importlib.util, json, os, sys
path, name = sys.argv[1], sys.argv[2]
inputs = json.loads(os.environ["VERIFY_INPUTS"])
expected = json.loads(os.environ["VERIFY_EXPECTED"])
spec = importlib.util.spec_from_file_location("submitted_ws_handler", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
fn = getattr(module, name)
values = [fn(n) for n in inputs]
if any(isinstance(v, bool) or not isinstance(v, int) for v in values):
    raise SystemExit(2)
if values != expected:
    raise SystemExit(3)
'''
    env = os.environ.copy()
    env["VERIFY_INPUTS"] = json.dumps(inputs)
    env["VERIFY_EXPECTED"] = json.dumps(expected)

    matching = []
    for name in function_names:
        try:
            result = subprocess.run(
                [sys.executable, "-c", checker, WS_HANDLER, name],
                cwd=BUILD_ENV_DIR, env=env, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True, timeout=8
            )
        except subprocess.TimeoutExpired:
            continue
        if result.returncode == 0:
            matching.append(name)

    assert matching, \
        "No function in ws_handler.py returns correct Collatz lengths for varied runtime inputs"


def test_json_payload_exists_and_correct():
    """Check if ws_payload.json exists and has the correct schema and values."""
    assert os.path.isfile(WS_PAYLOAD), f"JSON payload not found at {WS_PAYLOAD}"

    with open(WS_PAYLOAD, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{WS_PAYLOAD} does not contain valid JSON")

    assert isinstance(data, dict), "JSON payload must be an object"
    assert set(data) == {"channel", "message"}, "JSON payload does not follow the required schema"
    assert "channel" in data, "Key 'channel' missing from JSON payload"
    assert data["channel"] == "math_ws", f"Expected channel 'math_ws', got '{data['channel']}'"

    assert "message" in data, "Key 'message' missing from JSON payload"
    message = data["message"]
    assert isinstance(message, dict), "message must be a JSON object"
    assert set(message) == {"type", "start_val", "steps"}, \
        "message does not follow the required schema"

    assert "type" in message, "Key 'type' missing from message object"
    assert message["type"] == "collatz_len", f"Expected type 'collatz_len', got '{message['type']}'"

    assert "start_val" in message, "Key 'start_val' missing from message object"
    assert message["start_val"] == 837799, f"Expected start_val 837799, got {message['start_val']}"

    assert "steps" in message, "Key 'steps' missing from message object"
    assert isinstance(message["steps"], int) and not isinstance(message["steps"], bool), \
        "steps must be an integer"

    expected_steps = collatz_length(837799)
    assert message["steps"] == expected_steps, f"Expected steps {expected_steps}, got {message['steps']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
