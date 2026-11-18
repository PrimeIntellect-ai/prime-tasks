#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import asyncio
import json
import os
import re
import socket
import subprocess
import sys
import time

MATH_API = "/home/user/math_api.py"
CLIENT = "/home/user/test_client.py"
OUTPUT = "/home/user/test_output.json"
MPROF = "/home/user/mprof.dat"
EXPECTED_OUTPUT = ["42", "25.0", "72", "36", "ERROR"]


def stop_process(proc):
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=3)


def wait_for_port(proc, timeout=12):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            raise AssertionError("Server exited before listening on port 8080")
        sock = socket.socket()
        sock.settimeout(0.2)
        try:
            sock.connect(("127.0.0.1", 8080))
            return
        except OSError:
            time.sleep(0.1)
        finally:
            sock.close()
    raise AssertionError("Server did not listen on port 8080")


def wait_for_exit(proc, timeout=12):
    try:
        proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        stop_process(proc)
        raise AssertionError("Server did not exit after receiving SHUTDOWN")


def assert_output_file():
    assert os.path.isfile(OUTPUT), f"File {OUTPUT} is missing."
    try:
        with open(OUTPUT) as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"{OUTPUT} is not valid JSON: {exc}")
    assert isinstance(data, list), f"{OUTPUT} must contain a JSON array"
    str_data = [str(x) for x in data]
    assert str_data == EXPECTED_OUTPUT, (
        f"Expected {EXPECTED_OUTPUT}, but got {str_data} in {OUTPUT}."
    )


def check_original_assertions():
    assert os.path.isfile(MATH_API), f"File {MATH_API} is missing."
    with open(MATH_API) as f:
        content = f.read()

    assert "eval(" not in content, "math_api.py still contains the unsafe eval() function."
    assert "ast" in content, "math_api.py does not use the ast module for safe evaluation."

    history_bounded = (
        re.search(r'maxlen\s*=\s*10|pop\(0\)|\[-10:\]|del\s+history\[0\]|history\.pop\(0\)', content)
        or re.search(r'len\(history\)\s*>\s*10', content)
        or re.search(r'len\(history\)\s*>=\s*10', content)
        or re.search(r'len\(history\)\s*==\s*11', content)
    )
    assert history_bounded, "math_api.py does not appear to bound the history list to 10 items."
    assert os.path.isfile(CLIENT), f"File {CLIENT} is missing."


def run_profiled_integration():
    for path in (OUTPUT, MPROF):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    proc = subprocess.Popen(
        ["mprof", "run", "--output", MPROF, "python", MATH_API],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    try:
        wait_for_port(proc)
        client = subprocess.run(
            [sys.executable, CLIENT],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=20,
        )
        assert client.returncode == 0, f"test_client.py failed:\n{client.stdout}"
        wait_for_exit(proc)
    finally:
        stop_process(proc)

    assert_output_file()
    assert os.path.isfile(MPROF), f"File {MPROF} is missing."
    with open(MPROF) as f:
        first_line = f.readline()
    assert first_line.startswith("CMDLINE"), f"{MPROF} does not appear to be a valid mprof data file."
    assert "math_api.py" in first_line, f"{MPROF} was not run on math_api.py."


async def probe_server(messages, expected):
    import websockets

    uri = "ws://localhost:8080"
    async with websockets.connect(uri) as ws:
        responses = []
        for message in messages:
            await ws.send(message)
            responses.append(await asyncio.wait_for(ws.recv(), timeout=3))
        await ws.send("SHUTDOWN")

    assert len(responses) == len(expected)
    for expression, actual, wanted in zip(messages, responses, expected):
        if wanted == "ERROR":
            assert actual == "ERROR", f"Unsafe/unsupported expression {expression!r} returned {actual!r}"
        else:
            try:
                number = float(actual)
            except ValueError:
                raise AssertionError(f"Expression {expression!r} returned non-numeric {actual!r}")
            assert abs(number - wanted) < 1e-9, (
                f"Expression {expression!r} returned {actual!r}, expected {wanted}"
            )


def run_runtime_security_and_history_test():
    trace_path = "/tmp/history_trace.json"
    launcher_path = "/tmp/traced_server.py"
    marker = "/tmp/verifier_math_api_pwned"
    for path in (trace_path, marker):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    with open(launcher_path, "w") as f:
        f.write(r'''import json
import runpy
import sys

latest = None

def tracer(frame, event, arg):
    global latest
    if event == "line":
        candidate = frame.f_globals.get("history")
        if candidate is not None and not isinstance(candidate, (str, bytes, dict)):
            try:
                len(candidate)
                iter(candidate)
                latest = candidate
            except Exception:
                pass
    return tracer

sys.settrace(tracer)
try:
    runpy.run_path("/home/user/math_api.py", run_name="__main__")
finally:
    sys.settrace(None)
    payload = {"found": latest is not None}
    if latest is not None:
        try:
            payload["length"] = len(latest)
            payload["items"] = list(latest)
        except Exception as exc:
            payload["error"] = repr(exc)
    with open("/tmp/history_trace.json", "w") as out:
        json.dump(payload, out)
''')

    messages = [
        "1 + 1", "2 + 2", "3 + 3", "4 + 4", "5 + 5",
        "6 + 6", "7 + 7", "8 + 8", "9 + 9", "10 + 10",
        "7 + 5 * 3", "(20 - 2) / 3", "-8 + 3",
        "2 ** 8", "9 // 2", "abs(-3)", "True + 1",
        "__import__('os').system('touch /tmp/verifier_math_api_pwned')",
    ]
    expected = [
        2, 4, 6, 8, 10, 12, 14, 16, 18, 20,
        22, 6, -5, "ERROR", "ERROR", "ERROR", "ERROR", "ERROR",
    ]

    proc = subprocess.Popen(
        [sys.executable, launcher_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    try:
        wait_for_port(proc)
        asyncio.run(probe_server(messages, expected))
        wait_for_exit(proc)
    finally:
        stop_process(proc)

    assert not os.path.exists(marker), "A malicious expression executed an operating-system command"
    assert os.path.isfile(trace_path), "Could not inspect the server's runtime history"
    with open(trace_path) as f:
        history = json.load(f)
    assert history.get("found"), "No global history sequence was observed at runtime"
    assert history.get("length") == 10, f"Runtime history length was {history.get('length')}, not 10"
    assert history.get("items") == messages[-10:], (
        f"Runtime history did not retain exactly the newest 10 messages: {history.get('items')!r}"
    )


def run_client_protocol_test():
    oracle_path = "/tmp/client_oracle.py"
    record_path = "/tmp/client_protocol.json"
    try:
        os.remove(record_path)
    except FileNotFoundError:
        pass

    with open(oracle_path, "w") as f:
        f.write(r'''import asyncio
import json
import websockets

expected = ["15 + 27", "100 / 4", "8 * 9", "50 - 14", "__import__('os').system('echo hacked')"]
answers = ["42", "25.0", "72", "36", "ERROR"]
record = {"messages": [], "waited": True}

async def handler(ws, *args):
    pending = None
    for answer in answers:
        if pending is None:
            msg = await asyncio.wait_for(ws.recv(), timeout=5)
        else:
            msg, pending = pending, None
        record["messages"].append(msg)
        try:
            pending = await asyncio.wait_for(ws.recv(), timeout=0.12)
            record["waited"] = False
        except asyncio.TimeoutError:
            pass
        await ws.send(answer)
    if pending is None:
        pending = await asyncio.wait_for(ws.recv(), timeout=5)
    record["messages"].append(pending)
    with open("/tmp/client_protocol.json", "w") as out:
        json.dump(record, out)
    server.close()

async def main():
    global server
    server = await websockets.serve(handler, "localhost", 8080)
    await server.wait_closed()

asyncio.run(main())
''')

    oracle = subprocess.Popen(
        [sys.executable, oracle_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    try:
        wait_for_port(oracle)
        client = subprocess.run(
            [sys.executable, CLIENT],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=20,
        )
        assert client.returncode == 0, f"test_client.py failed against protocol server:\n{client.stdout}"
        wait_for_exit(oracle)
    finally:
        stop_process(oracle)

    assert os.path.isfile(record_path), "The client did not complete the WebSocket protocol"
    with open(record_path) as f:
        record = json.load(f)
    required = [
        "15 + 27", "100 / 4", "8 * 9", "50 - 14",
        "__import__('os').system('echo hacked')", "SHUTDOWN",
    ]
    assert record.get("messages") == required, f"Client sent the wrong sequence: {record.get('messages')!r}"
    assert record.get("waited") is True, "Client sent another expression before receiving the prior response"
    assert_output_file()


def main():
    check_original_assertions()
    run_profiled_integration()
    run_runtime_security_and_history_test()
    run_client_protocol_test()


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
