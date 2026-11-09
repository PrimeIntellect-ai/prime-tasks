#!/bin/bash
set +e
mkdir -p /logs/verifier
export PATH="/root/.cargo/bin:${PATH}"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os


def test_math_success_log_exists():
    log_path = "/home/user/math_success.log"
    assert os.path.isfile(log_path), f"Expected output file {log_path} does not exist. Did the Python script run successfully?"


def test_math_success_log_content():
    log_path = "/home/user/math_success.log"
    assert os.path.isfile(log_path), f"Expected output file {log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read()
    expected_content = "RESULT: 120\n"
    assert content == expected_content, f"Content of {log_path} is incorrect. Expected {repr(expected_content)}, but got {repr(content)}"


def test_rust_server_compiled():
    binary_path = "/home/user/math_feature/server"
    assert os.path.isfile(binary_path), f"Expected compiled Rust binary {binary_path} does not exist. Did you compile server.rs?"
    assert os.access(binary_path, os.X_OK), f"The file {binary_path} exists but is not executable."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The server executable is not a compiled ELF binary."
TEST_EOF

status=0
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || status=1

rm -rf /tmp/math_verifier_target
if [ "$status" -eq 0 ]; then
    timeout 180 cargo build --offline \
        --manifest-path /home/user/math_feature/Cargo.toml \
        --target-dir /tmp/math_verifier_target >/tmp/math_verifier_cargo.log 2>&1 || {
        cat /tmp/math_verifier_cargo.log
        status=1
    }
fi

if [ "$status" -eq 0 ]; then
cat << 'PY_EOF' > /tmp/verify_math_e2e.py
import asyncio
import json
import os
import secrets
import signal
import subprocess
import sys
import time

import websockets

PORT_HEX = format(8765, "04X")
LOG = "/home/user/math_success.log"
TEST_SCRIPT = "/home/user/math_feature/test_e2e.py"


def kill_port_owner():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(":")[-1].upper() == PORT_HEX and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    if not inodes:
        return
    me = os.getpid()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == me:
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    try:
                        os.kill(int(name), signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    break
        except (FileNotFoundError, PermissionError):
            pass
    time.sleep(0.3)


async def run_test_script():
    proc = await asyncio.create_subprocess_exec(
        sys.executable, TEST_SCRIPT,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=20)
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        raise AssertionError("test_e2e.py timed out")
    assert proc.returncode == 0, (
        f"test_e2e.py failed with code {proc.returncode}\n"
        f"stdout: {stdout.decode(errors='replace')}\n"
        f"stderr: {stderr.decode(errors='replace')}"
    )


async def verify_python_client():
    kill_port_owner()
    captured = []
    reply = secrets.randbelow(800000) + 100001

    async def handler(ws, *args):
        message = await asyncio.wait_for(ws.recv(), timeout=10)
        captured.append(message)
        await ws.send(str(reply))

    async with websockets.serve(handler, "127.0.0.1", 8765):
        if os.path.exists(LOG):
            os.unlink(LOG)
        await run_test_script()

    assert len(captured) == 1, f"Expected one WebSocket payload, received {len(captured)}"
    assert isinstance(captured[0], str), "The E2E client did not send a text JSON payload"
    try:
        payload = json.loads(captured[0])
    except Exception as exc:
        raise AssertionError(f"The E2E payload is not valid JSON: {exc}")
    assert payload == {"data": [2, 4, 6, 8]}, f"Incorrect E2E payload: {payload!r}"
    with open(LOG) as f:
        content = f.read()
    assert content == f"RESULT: {reply}\n", (
        "test_e2e.py did not deserialize the server response and write the resulting value"
    )


async def connect_and_request(values):
    last_error = None
    for _ in range(40):
        try:
            async with websockets.connect("ws://127.0.0.1:8765", open_timeout=1) as ws:
                await ws.send(json.dumps({"data": values}))
                response = await asyncio.wait_for(ws.recv(), timeout=5)
                return response
        except Exception as exc:
            last_error = exc
            await asyncio.sleep(0.1)
    raise AssertionError(f"Could not communicate with server: {last_error}")


def stop_process(proc):
    if proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
            proc.wait(timeout=3)
        except Exception:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=3)
    kill_port_owner()


async def verify_server(binary, run_e2e):
    kill_port_owner()
    proc = subprocess.Popen(
        [binary], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        cases = []
        for _ in range(4):
            values = [secrets.randbelow(41) - 20 for _ in range(secrets.randbelow(6) + 2)]
            cases.append(values)
        cases.append([0, -3, 11, -7])
        for values in cases:
            response = await connect_and_request(values)
            expected = sum(value * value for value in values)
            assert str(response) == str(expected), (
                f"Server returned {response!r} for {values!r}; expected {expected}"
            )

        if run_e2e:
            if os.path.exists(LOG):
                os.unlink(LOG)
            await run_test_script()
            assert os.path.isfile(LOG), "Running test_e2e.py did not create math_success.log"
            with open(LOG) as f:
                content = f.read()
            assert content == "RESULT: 120\n", f"Final E2E output was {content!r}"
    finally:
        stop_process(proc)


async def main():
    await verify_python_client()
    await verify_server("/tmp/math_verifier_target/debug/math_server", False)
    await verify_server("/home/user/math_feature/server", True)


asyncio.run(main())
PY_EOF
    timeout 120 python3 /tmp/verify_math_e2e.py 2>&1 || status=1
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
