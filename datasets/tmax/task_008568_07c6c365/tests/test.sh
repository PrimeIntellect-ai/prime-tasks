#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import glob
import importlib.metadata
import json
import os
import secrets
import shutil
import subprocess
import sys
import time

import pytest
import websockets

PROJECT = "/home/user/math_server"


def collatz_reference(n):
    steps = 0
    while n > 1:
        n = n // 2 if n % 2 == 0 else 3 * n + 1
        steps += 1
    return steps


def stop_existing_servers():
    subprocess.run(
        ["pkill", "-f", "[p]ython3 .*server.py"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    time.sleep(0.3)


def test_build_system_actually_builds_optimized_extension():
    setup_path = os.path.join(PROJECT, "setup.py")
    assert os.path.isfile(setup_path), f"The file {setup_path} is missing."

    with open(setup_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "ENABLE_OPT" in content, "setup.py does not seem to check for the ENABLE_OPT environment variable."
    assert "USE_OPTIMIZED" in content, "setup.py does not seem to pass the USE_OPTIMIZED macro."
    assert "websockets" in content, "setup.py does not define 'websockets' as a dependency."

    compiler_log = "/tmp/compiler_args.log"
    wrapper = "/tmp/cc-wrapper.sh"
    with open(wrapper, "w") as f:
        f.write("#!/bin/sh\nprintf '%s\\n' \"$*\" >> /tmp/compiler_args.log\nexec /usr/bin/gcc \"$@\"\n")
    os.chmod(wrapper, 0o755)
    if os.path.exists(compiler_log):
        os.unlink(compiler_log)

    shutil.rmtree(os.path.join(PROJECT, "build"), ignore_errors=True)
    for artifact in glob.glob(os.path.join(PROJECT, "fastmath*.so")):
        os.unlink(artifact)

    env = os.environ.copy()
    env["ENABLE_OPT"] = "1"
    env["CC"] = wrapper
    result = subprocess.run(
        [sys.executable, "-m", "pip", "install", ".", "--force-reinstall", "--no-deps", "--no-build-isolation", "--no-cache-dir"],
        cwd=PROJECT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert result.returncode == 0, f"ENABLE_OPT=1 pip install . failed:\n{result.stdout}"
    assert os.path.isfile(compiler_log), "The C source was not compiled during installation."
    with open(compiler_log) as f:
        invocations = f.read().splitlines()
    assert any(
        any(arg == "-DUSE_OPTIMIZED" or arg.startswith("-DUSE_OPTIMIZED=") for arg in line.split())
        for line in invocations
    ), f"The compiler was not passed -DUSE_OPTIMIZED when ENABLE_OPT=1. Invocations: {invocations}"

    requirements = importlib.metadata.requires("FastMath") or []
    assert any(req.split(";", 1)[0].strip().lower().startswith("websockets") for req in requirements), \
        f"Installed package metadata does not declare websockets: {requirements}"


def test_fastmath_extension_installed_and_fixed():
    # Preserve the original import and fixed-input assertions.
    try:
        import fastmath
    except ImportError:
        pytest.fail("The fastmath module is not installed or importable. Did you run 'pip install .'?")

    try:
        steps_15 = fastmath.collatz(15)
        steps_27 = fastmath.collatz(27)
    except Exception as e:
        pytest.fail(f"Calling fastmath.collatz failed with: {e}")

    assert steps_15 == 17, f"fastmath.collatz(15) returned {steps_15}, expected 17. The C extension logic bug might not be fixed."
    assert steps_27 == 111, f"fastmath.collatz(27) returned {steps_27}, expected 111."

    # Exercise the freshly optimized build on verifier-derived inputs.
    values = [2, 3, 7, 31, 97, 999999, 1000000]
    values.extend(2 + secrets.randbelow(999999) for _ in range(20))
    for value in values:
        assert fastmath.collatz(value) == collatz_reference(value), \
            f"fastmath.collatz({value}) is incorrect in the ENABLE_OPT=1 build"


def test_server_py_validation_and_live_behavior():
    server_path = os.path.join(PROJECT, "server.py")
    assert os.path.isfile(server_path), f"The file {server_path} is missing."

    with open(server_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "ERROR: Invalid input" in content, "server.py does not contain the exact error message 'ERROR: Invalid input'."
    assert "1000000" in content, "server.py does not seem to check the upper bound of 1000000."

    stop_existing_servers()
    proc = subprocess.Popen(
        [sys.executable, "server.py"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    random_valid = 2 + secrets.randbelow(999999)
    requests = [
        (str(random_valid), str(collatz_reference(random_valid))),
        ("15", "17"),
        ("27", "111"),
        ("1000000", str(collatz_reference(1000000))),
        ("0", "ERROR: Invalid input"),
        ("-8", "ERROR: Invalid input"),
        ("1000001", "ERROR: Invalid input"),
        ("2000000", "ERROR: Invalid input"),
        ("not-an-integer", "ERROR: Invalid input"),
        ("2.5", "ERROR: Invalid input"),
    ]

    async def exercise_server():
        last_error = None
        for _ in range(40):
            if proc.poll() is not None:
                output = proc.stdout.read() if proc.stdout else ""
                pytest.fail(f"server.py exited before accepting connections:\n{output}")
            try:
                async with websockets.connect("ws://localhost:8765", open_timeout=1) as ws:
                    for message, expected in requests:
                        await ws.send(message)
                        response = await asyncio.wait_for(ws.recv(), timeout=2)
                        assert response == expected, \
                            f"Server response for {message!r} was {response!r}, expected {expected!r}"
                    return
            except (OSError, asyncio.TimeoutError) as exc:
                last_error = exc
                await asyncio.sleep(0.15)
        pytest.fail(f"Could not connect to server.py on port 8765: {last_error}")

    try:
        asyncio.run(exercise_server())
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)
        stop_existing_servers()


def test_test_client_sh_exists_and_performs_exchange():
    script_path = "/home/user/test_client.sh"
    log_path = "/home/user/test_results.log"
    assert os.path.isfile(script_path), f"The script {script_path} is missing."

    stop_existing_servers()
    if os.path.exists(log_path):
        os.unlink(log_path)
    record_path = "/tmp/client_messages.jsonl"
    if os.path.exists(record_path):
        os.unlink(record_path)

    fake_server = r'''
import asyncio
import json
import websockets

record = "/tmp/client_messages.jsonl"

def collatz(n):
    steps = 0
    while n > 1:
        n = n // 2 if n % 2 == 0 else 3 * n + 1
        steps += 1
    return steps

async def handler(ws, *args):
    async for message in ws:
        with open(record, "a") as f:
            f.write(json.dumps(message) + "\\n")
            f.flush()
        try:
            n = int(message)
            if str(n) != message or n < 1 or n > 1000000:
                raise ValueError
            response = str(collatz(n))
        except Exception:
            response = "ERROR: Invalid input"
        await ws.send(response)

async def main():
    async with websockets.serve(handler, "localhost", 8765):
        await asyncio.Future()

asyncio.run(main())
'''
    recorder = subprocess.Popen(
        [sys.executable, "-c", fake_server],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    try:
        time.sleep(1)
        if recorder.poll() is not None:
            pytest.fail(f"Verifier WebSocket server failed to start:\n{recorder.stdout.read()}")
        result = subprocess.run(
            ["bash", script_path],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=30,
        )
        assert result.returncode == 0, f"test_client.sh failed:\n{result.stdout}"
        time.sleep(0.3)
    finally:
        recorder.terminate()
        try:
            recorder.wait(timeout=3)
        except subprocess.TimeoutExpired:
            recorder.kill()
            recorder.wait(timeout=3)

    observed = []
    if os.path.isfile(record_path):
        with open(record_path) as f:
            observed = [json.loads(line) for line in f if line.strip()]
    assert observed == ["15", "2000000", "27"], \
        f"test_client.sh did not send the required three messages in order; observed {observed}"

    # Preserve the original test_results.log assertion, but only after executing the client.
    assert os.path.isfile(log_path), f"The file {log_path} is missing. Did you run test_client.sh?"
    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    expected = ["17", "ERROR: Invalid input", "111"]
    assert lines == expected, f"Contents of {log_path} do not match expected output. Got {lines}, expected {expected}."
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
