#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import json
import os
import random
import re
import subprocess
import tempfile

import pytest
import websockets

URI = "ws://127.0.0.1:8081"
TOKEN = "omega-build-99"


def compile_and_count(c_code, instruction_only=False):
    """Independently cross-compile source and count mov instructions."""
    with tempfile.TemporaryDirectory() as td:
        temp_c = os.path.join(td, "input.c")
        temp_s = os.path.join(td, "output.s")
        with open(temp_c, "w") as f:
            f.write(c_code)

        try:
            subprocess.run(
                ["aarch64-linux-gnu-gcc", "-S", "-O0", temp_c, "-o", temp_s],
                check=True,
                capture_output=True,
            )
        except FileNotFoundError:
            pytest.fail("aarch64-linux-gnu-gcc is not installed or not in PATH.")
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Failed to compile C code for truth generation: {e.stderr.decode()}")

        with open(temp_s, "r") as f:
            lines = f.readlines()

    if instruction_only:
        # Match an assembly instruction mnemonic, not occurrences in directives,
        # strings, comments, symbols, or filenames.
        pattern = re.compile(
            r"^\s*(?:[A-Za-z_.$][A-Za-z0-9_.$]*:\s*)?mov(?:\s|$)", re.IGNORECASE
        )
    else:
        # Retain the original verifier's expected-count calculation for its
        # original fixed test case.
        pattern = re.compile(r"\bmov\b", re.IGNORECASE)

    return sum(1 for line in lines if pattern.search(line))


async def receive_result(c_code):
    try:
        async with websockets.connect(URI) as ws:
            await ws.send(json.dumps({"token": TOKEN, "c_code": c_code}))
            response = await asyncio.wait_for(ws.recv(), timeout=10)
    except ConnectionRefusedError:
        pytest.fail("Could not connect to WebSocket server on 127.0.0.1:8081.")

    try:
        return json.loads(response)
    except json.JSONDecodeError:
        pytest.fail(f"Server did not return valid JSON. Response: {response}")


async def assert_invalid_token_closed(token="wrong"):
    try:
        async with websockets.connect(URI) as ws:
            payload = {"token": token, "c_code": "int main(){}"}
            await ws.send(json.dumps(payload))
            try:
                await asyncio.wait_for(ws.recv(), timeout=10)
                pytest.fail("Connection was not closed as expected.")
            except websockets.exceptions.ConnectionClosed as e:
                assert e.code == 1008, f"Expected close code 1008 for invalid token, got {e.code}"
    except ConnectionRefusedError:
        pytest.fail("Could not connect to WebSocket server on 127.0.0.1:8081.")


def test_websocket_server_invalid_token():
    """Test that the server closes the connection with code 1008 for an invalid token."""
    asyncio.run(assert_invalid_token_closed())


def test_websocket_server_valid_token():
    """Retain the original fixed compilation and response assertions."""
    c_code = "int main() { int a = 5; int b = a; return b; }"
    expected_count = compile_and_count(c_code, instruction_only=False)
    data = asyncio.run(receive_result(c_code))

    assert data.get("result") == "compiled", f"Expected result 'compiled', got {data.get('result')}"
    assert data.get("mov_count") == expected_count, \
        f"Expected mov_count {expected_count}, got {data.get('mov_count')}"


def test_randomized_programs_and_subsequent_connections():
    """Exercise fresh, unpredictable programs over multiple later connections."""
    rng = random.SystemRandom()
    nonce = os.urandom(8).hex()
    mov_repetitions = rng.sample(range(1, 13), 6)
    cases = []

    for index, repetitions in enumerate(mov_repetitions):
        constants = [rng.randrange(1, 100000) for _ in range(rng.randrange(2, 7))]
        operations = "\n".join(
            f"    value += {constant};" for constant in constants
        )
        inline_movs = "\\n\\t".join("mov x9, x9" for _ in range(repetitions))
        source = f'''\n/* Random case {nonce}; the word mov in this comment is not an instruction. */\nconst char marker_{nonce}_{index}[] = "mov is data, not an instruction";\n\nint movement_{nonce}_{index}(int input) {{\n    volatile int value = input;\n{operations}\n    __asm__ volatile ("{inline_movs}" : : : "x9");\n    return value;\n}}\n\nint main(void) {{\n    return movement_{nonce}_{index}({rng.randrange(1, 1000)});\n}}\n'''
        cases.append((source, compile_and_count(source, instruction_only=True)))

    async def run_sequence():
        observed = []
        for index, (source, expected_count) in enumerate(cases):
            # An invalid connection in the middle must not terminate the worker.
            if index == 3:
                await assert_invalid_token_closed("wrong-" + os.urandom(6).hex())

            data = await receive_result(source)
            assert data.get("result") == "compiled", \
                f"Expected result 'compiled', got {data.get('result')}"
            assert isinstance(data.get("mov_count"), int), "mov_count must be an integer"
            assert data.get("mov_count") == expected_count, \
                f"Expected mov_count {expected_count}, got {data.get('mov_count')}"
            observed.append(data.get("mov_count"))

        # The generated inline-assembly counts are distinct, so a single fixed
        # response cannot satisfy all of the independently compiled cases.
        assert len(set(observed)) > 1, "Generated cases did not exercise differing mov counts"

    asyncio.run(run_sequence())
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
