#!/bin/bash
mkdir -p /logs/verifier

cleanup() {
    pkill -f '/home/user/build_server.py' >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup
sleep 0.2

cat <<'PY_EOF' > /tmp/verify_build_server.py
import asyncio
import json
import os
import random
import string
import subprocess
import time

import websockets
from websockets.exceptions import ConnectionClosed

SERVER = "/home/user/build_server.py"
SCHEDULE = "/home/user/build_schedule.json"


def start_server():
    if os.path.exists(SCHEDULE):
        os.remove(SCHEDULE)
    proc = subprocess.Popen(
        ["python3", SERVER],
        cwd="/home/user",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    return proc


def stop_server(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=1)


async def connect_with_retry(proc):
    last_error = None
    for _ in range(50):
        if proc.poll() is not None:
            raise AssertionError(f"build_server.py exited before accepting a connection (status {proc.returncode})")
        try:
            return await websockets.connect("ws://localhost:9000", open_timeout=0.5)
        except Exception as exc:
            last_error = exc
            await asyncio.sleep(0.05)
    raise AssertionError(f"Could not connect to WebSocket server on localhost:9000: {last_error}")


def load_schedule():
    assert os.path.exists(SCHEDULE), f"The file {SCHEDULE} was not created."
    assert os.path.isfile(SCHEDULE), f"The path {SCHEDULE} is not a file."
    try:
        with open(SCHEDULE, "r") as f:
            schedule = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"The file {SCHEDULE} does not contain valid JSON.") from exc
    return schedule


def assert_schedule(expected_schedule):
    schedule = load_schedule()
    assert isinstance(schedule, list), "The JSON root must be a list of objects."
    assert len(schedule) == len(expected_schedule), (
        f"Expected {len(expected_schedule)} tasks in schedule, but found {len(schedule)}."
    )
    for i, (actual, expected) in enumerate(zip(schedule, expected_schedule)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."
        assert actual.get("task") == expected["task"], (
            f"Expected task '{expected['task']}' at step {i + 1}, got '{actual.get('task')}'."
        )
        assert actual.get("worker") == expected["worker"], (
            f"Expected worker '{expected['worker']}' for task '{expected['task']}' at step {i + 1}, "
            f"got '{actual.get('worker')}'."
        )


async def wait_for_exit(proc, timeout=3):
    deadline = time.monotonic() + timeout
    while proc.poll() is None and time.monotonic() < deadline:
        await asyncio.sleep(0.05)
    assert proc.poll() is not None, "build_server.py did not shut down after finishing the build"


async def assert_server_stopped():
    await asyncio.sleep(0.1)
    try:
        ws = await websockets.connect("ws://localhost:9000", open_timeout=0.3)
    except Exception:
        return
    await ws.close()
    raise AssertionError("WebSocket server was still accepting connections after the build completed")


async def run_success(workers, dsl_script, expected, blocked_after=None):
    proc = start_server()
    try:
        ws = await connect_with_retry(proc)
        try:
            await ws.send(json.dumps({"type": "workers", "data": workers}))
            await ws.send(json.dumps({"type": "dsl", "script": dsl_script}))

            for index, item in enumerate(expected):
                raw = await asyncio.wait_for(ws.recv(), timeout=3)
                message = json.loads(raw)
                assert message == {
                    "type": "execute",
                    "task": item["task"],
                    "worker": item["worker"],
                }, f"Unexpected execution command at position {index}: {message!r}"

                if blocked_after is not None and item["task"] in blocked_after:
                    try:
                        early = await asyncio.wait_for(ws.recv(), timeout=0.3)
                    except asyncio.TimeoutError:
                        pass
                    else:
                        raise AssertionError(
                            f"Server dispatched a dependent before receiving completion: {early!r}"
                        )

                await ws.send(json.dumps({"type": "completed", "task": item["task"]}))

            raw = await asyncio.wait_for(ws.recv(), timeout=3)
            message = json.loads(raw)
            assert message == {"type": "done"}, f"Expected final done message, got {message!r}"
        finally:
            await ws.close()

        await wait_for_exit(proc)
        assert_schedule(expected)
        await assert_server_stopped()
    finally:
        stop_server(proc)


async def test_original_case():
    workers = {
        "w-linux-gcc": ["gcc", "make", "bash"],
        "w-mac-clang": ["clang", "make", "bash"],
        "w-windows-msvc": ["msvc", "cmake", "powershell"],
        "w-polyglot": ["gcc", "python", "node", "bash"],
    }
    dsl_script = """
TARGET init
REQUIRES bash
END

TARGET compile_c
REQUIRES gcc
REQUIRES make
AFTER init
END

TARGET compile_py
REQUIRES python
AFTER init
END

TARGET link
REQUIRES bash
AFTER compile_c
AFTER compile_py
END

TARGET package
REQUIRES node
AFTER link
END
"""
    expected = [
        {"task": "init", "worker": "w-linux-gcc"},
        {"task": "compile_c", "worker": "w-linux-gcc"},
        {"task": "compile_py", "worker": "w-polyglot"},
        {"task": "link", "worker": "w-linux-gcc"},
        {"task": "package", "worker": "w-polyglot"},
    ]
    await run_success(workers, dsl_script, expected)


async def test_dynamic_parsing_constraints_and_waiting():
    token = "".join(random.SystemRandom().choices(string.ascii_lowercase, k=10))
    root = f"root_{token}"
    child_z = f"zchild_{token}"
    child_a = f"achild_{token}"
    final = f"final_{token}"

    worker_a = f"a_{token}"
    worker_m = f"m_{token}"
    worker_z = f"z_{token}"
    workers = {
        worker_z: ["alpha", "beta"],
        worker_m: ["alpha", "beta", "gamma"],
        worker_a: ["alpha"],
    }

    # Children deliberately appear in reverse lexical order. Unknown lines must be ignored.
    dsl_script = f"""
THIS LINE IS IGNORED
TARGET {root}
REQUIRES alpha
NOT_A_DIRECTIVE anything
END
TARGET {child_z}
REQUIRES beta
AFTER {root}
END
TARGET {child_a}
REQUIRES alpha
AFTER {root}
END
TARGET {final}
REQUIRES alpha
REQUIRES beta
REQUIRES gamma
AFTER {child_z}
AFTER {child_a}
END
"""
    expected = [
        {"task": root, "worker": worker_a},
        {"task": child_a, "worker": worker_a},
        {"task": child_z, "worker": worker_m},
        {"task": final, "worker": worker_m},
    ]
    # No target can legally follow root before root completes, and final cannot follow
    # child_z until child_z completes. These checks exercise completion waiting.
    await run_success(workers, dsl_script, expected, blocked_after={root, child_z})


async def test_unassignable_target_fails():
    proc = start_server()
    try:
        ws = await connect_with_retry(proc)
        try:
            await ws.send(json.dumps({"type": "workers", "data": {"only-worker": ["python"]}}))
            await ws.send(json.dumps({
                "type": "dsl",
                "script": "TARGET impossible\nREQUIRES unavailable_tool\nEND\n",
            }))
            try:
                message = await asyncio.wait_for(ws.recv(), timeout=2)
            except ConnectionClosed:
                pass
            except asyncio.TimeoutError as exc:
                raise AssertionError("Server did not immediately drop the connection for an unassignable target") from exc
            else:
                raise AssertionError(f"Server sent a message instead of failing an unassignable build: {message!r}")
        finally:
            await ws.close()
        await wait_for_exit(proc)
    finally:
        stop_server(proc)


async def main():
    assert os.path.exists(SERVER), f"Required artifact {SERVER} does not exist"
    assert os.path.isfile(SERVER), f"Required artifact {SERVER} is not a regular file"
    assert os.path.getsize(SERVER) > 0, f"Required artifact {SERVER} is empty"
    await test_original_case()
    await test_dynamic_parsing_constraints_and_waiting()
    await test_unassignable_target_fails()


if __name__ == "__main__":
    asyncio.run(main())
PY_EOF

if python3 /tmp/verify_build_server.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
