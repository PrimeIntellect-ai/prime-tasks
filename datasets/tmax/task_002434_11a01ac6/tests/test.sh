#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop any server/client left running by the agent so the verifier can exercise
# the submitted client against an independent server on the required address.
pkill -f '/home/user/server.py' 2>/dev/null || true
pkill -f '/home/user/ws-eval-proxy/target/' 2>/dev/null || true
sleep 1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import base64
import os
import secrets
import subprocess

import websockets

PROJECT = "/home/user/ws-eval-proxy"
SOURCE = os.path.join(PROJECT, "src", "main.rs")
RESULTS = "/home/user/results.log"
EXPECTED_LOG = "SUCCESS: Protocol complete and validated.\n"


def test_results_log_exists():
    assert os.path.isfile(RESULTS), (
        f"The file {RESULTS} does not exist. Did you run the Python server and the Rust client?"
    )


def test_results_log_content():
    assert os.path.isfile(RESULTS), f"The file {RESULTS} does not exist."
    with open(RESULTS, "r") as f:
        content = f.read()
    assert content == EXPECTED_LOG, (
        f"Expected the log file to contain exactly {EXPECTED_LOG!r}, but got {content!r}."
    )


def test_rust_source_compiles_without_warnings():
    assert os.path.isfile(SOURCE), f"Missing Rust source file: {SOURCE}"
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Missing Cargo.toml"

    env = os.environ.copy()
    env["RUSTFLAGS"] = (env.get("RUSTFLAGS", "") + " -D warnings").strip()
    completed = subprocess.run(
        ["cargo", "check", "--all-targets", "--color", "never"],
        cwd=PROJECT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=240,
    )
    assert completed.returncode == 0, (
        "The Rust project did not compile cleanly with warnings denied:\n" + completed.stdout
    )


def make_cases():
    cases = []
    operations = ["+", "-", "*", "/"] * 4
    for op in operations:
        if op == "/":
            b = secrets.randbelow(18) + 2
            result = secrets.randbelow(40) + 1
            a = b * result
        else:
            a = secrets.randbelow(90) + 1
            b = secrets.randbelow(90) + 1
            if op == "+":
                result = a + b
            elif op == "-":
                result = a - b
            else:
                result = a * b
        expression = f"{a} {op} {b}"
        challenge = base64.b64encode(expression.encode("utf-8")).decode("ascii")
        cases.append((challenge, str(result)))
    return cases


async def run_protocol_test():
    cases = make_cases()
    loop = asyncio.get_running_loop()
    protocol_done = loop.create_future()

    async def handler(websocket):
        try:
            for challenge, expected in cases:
                await websocket.send(challenge)
                response = await asyncio.wait_for(websocket.recv(), timeout=10)
                assert response == expected, (
                    f"For challenge {challenge!r}, expected {expected!r}, got {response!r}"
                )
            await websocket.send("DONE")
            if not protocol_done.done():
                protocol_done.set_result(True)
        except BaseException as exc:
            if not protocol_done.done():
                protocol_done.set_exception(exc)

    env = os.environ.copy()
    env["RUSTFLAGS"] = (env.get("RUSTFLAGS", "") + " -D warnings").strip()
    proc = None
    try:
        async with websockets.serve(handler, "127.0.0.1", 8765):
            proc = await asyncio.create_subprocess_exec(
                "cargo", "run", "--quiet",
                cwd=PROJECT,
                env=env,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            await asyncio.wait_for(protocol_done, timeout=60)
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=20)
            assert proc.returncode == 0, (
                "The Rust client exited unsuccessfully.\n"
                f"stdout:\n{stdout.decode(errors='replace')}\n"
                f"stderr:\n{stderr.decode(errors='replace')}"
            )
    finally:
        if proc is not None and proc.returncode is None:
            proc.kill()
            await proc.communicate()


def test_client_handles_independently_generated_protocol():
    asyncio.run(run_protocol_test())
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
