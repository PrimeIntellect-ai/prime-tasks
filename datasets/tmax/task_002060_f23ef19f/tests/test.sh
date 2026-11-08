#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import signal
import subprocess
import time

import pytest

START = "/home/user/start_server.sh"
CLIENT = "/home/user/ws_client.sh"
SERVER = "/home/user/math_server.py"
EXPRESSIONS = "/home/user/expressions.txt"
LOG = "/home/user/evaluation_results.log"


def server_processes():
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            raw = open(f"/proc/{name}/cmdline", "rb").read()
            cmd = raw.replace(b"\0", b" ").decode(errors="replace")
        except (OSError, IOError):
            continue
        if SERVER in cmd:
            found.append((int(name), cmd))
    return found


def stop_servers():
    for pid, _ in server_processes():
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and server_processes():
        time.sleep(0.05)
    for pid, _ in server_processes():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def run_start(*args):
    before = time.monotonic()
    proc = subprocess.Popen(
        [START] + list(args),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    proc.wait(timeout=8)
    elapsed = time.monotonic() - before
    assert proc.returncode == 0, f"start_server.sh exited with {proc.returncode}"
    assert elapsed >= 1.5, "start_server.sh did not give the background server about 2 seconds to start"


def run_client():
    proc = subprocess.run(
        [CLIENT],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert proc.returncode == 0, f"ws_client.sh failed:\nstdout={proc.stdout}\nstderr={proc.stderr}"


def read_log():
    assert os.path.isfile(LOG), f"File {LOG} does not exist. Did you run the client script?"
    with open(LOG) as f:
        return [line.rstrip("\n") for line in f]


def bc_result(expr):
    return subprocess.check_output(["bc", "-l"], input=(expr + "\n").encode()).decode().strip()


def test_scripts_and_end_to_end_behavior():
    # Preserve the original verifier's source-level assertions.
    assert os.path.isfile(START), f"File {START} does not exist."
    with open(START) as f:
        start_content = f.read()
    assert "--py3" in start_content or "$1" in start_content or "$@" in start_content, \
        f"Script {START} does not seem to check for arguments."
    assert "python3" in start_content, f"Script {START} does not contain 'python3' for the --py3 flag."
    assert "python2" in start_content, f"Script {START} does not contain 'python2' as the default fallback."

    assert os.path.isfile(CLIENT), f"File {CLIENT} does not exist."
    with open(CLIENT) as f:
        client_content = f.read()
    assert "websocat" in client_content, f"Script {CLIENT} does not use 'websocat'."
    assert "bc" in client_content, f"Script {CLIENT} does not use 'bc' for fallback evaluation."
    assert "MIGRATION_ERROR" in client_content, f"Script {CLIENT} does not check for 'MIGRATION_ERROR'."
    assert os.access(START, os.X_OK), f"{START} is not executable"
    assert os.access(CLIENT, os.X_OK), f"{CLIENT} is not executable"

    original_expressions = "15 + 20\n100 / 3\n50 * 2\n7 / 2\n"
    expected_original = [
        "15 + 20 = 35",
        "100 / 3 = 33.33333333333333333333",
        "50 * 2 = 100",
        "7 / 2 = 3.50000000000000000000",
    ]

    # Execute the submitted runner against the supplied Python 3 server and
    # execute the submitted client on the task's original input.
    stop_servers()
    with open(EXPRESSIONS, "w") as f:
        f.write(original_expressions)
    try:
        os.unlink(LOG)
    except FileNotFoundError:
        pass
    try:
        run_start("--py3")
        procs = server_processes()
        assert procs, "start_server.sh returned but left no math_server.py running"
        assert any("python3" in cmd for _, cmd in procs), "--py3 did not launch math_server.py with python3"
        run_client()
        assert read_log() == expected_original, \
            f"evaluation_results.log was not exactly formatted as expected: {read_log()}"
    finally:
        stop_servers()

    # Use unpredictable inputs and a recording WebSocket server. This checks
    # that every expression is actually sent, that normal responses are read
    # and trimmed, and that MIGRATION_ERROR invokes bc -l.
    nonce = random.SystemRandom().randint(10000, 99999)
    dynamic = [
        f"{nonce} + 7",
        f"{nonce + 3} * 2",
        f"{nonce + 11} / 3",
        f"{nonce + 19} / 8",
    ]
    normal_one = str(nonce * 13 + 1)
    normal_two = str(nonce * 17 + 2)
    responses = {
        dynamic[0]: normal_one + "   ",
        dynamic[1]: normal_two + "\t",
        dynamic[2]: "MIGRATION_ERROR",
        dynamic[3]: "MIGRATION_ERROR",
    }
    expected_dynamic = [
        f"{dynamic[0]} = {normal_one}",
        f"{dynamic[1]} = {normal_two}",
        f"{dynamic[2]} = {bc_result(dynamic[2])}",
        f"{dynamic[3]} = {bc_result(dynamic[3])}",
    ]

    response_file = "/tmp/ws_responses.json"
    record_file = "/tmp/ws_received.jsonl"
    ready_file = "/tmp/ws_ready"
    with open(response_file, "w") as f:
        json.dump(responses, f)
    for path in (record_file, ready_file):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    helper = r'''import asyncio, json, os
from websockets.legacy.server import serve
responses = json.load(open("/tmp/ws_responses.json"))
async def handler(ws, path):
    async for message in ws:
        with open("/tmp/ws_received.jsonl", "a") as out:
            out.write(json.dumps(message) + "\\n")
            out.flush()
        await ws.send(responses.get(message.strip(), "UNEXPECTED_MESSAGE"))
async def main():
    async with serve(handler, "127.0.0.1", 8888):
        open("/tmp/ws_ready", "w").write("ready")
        await asyncio.Future()
asyncio.run(main())
'''
    with open("/tmp/recording_ws_server.py", "w") as f:
        f.write(helper)
    mock = subprocess.Popen(
        ["python3", "/tmp/recording_ws_server.py"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        deadline = time.time() + 5
        while time.time() < deadline and not os.path.exists(ready_file):
            if mock.poll() is not None:
                raise AssertionError(f"recording WebSocket server failed: {mock.stderr.read()}")
            time.sleep(0.05)
        assert os.path.exists(ready_file), "recording WebSocket server did not start"

        with open(EXPRESSIONS, "w") as f:
            f.write("\n".join(dynamic) + "\n")
        try:
            os.unlink(LOG)
        except FileNotFoundError:
            pass
        run_client()
        assert read_log() == expected_dynamic, \
            f"client output for dynamic inputs was incorrect: {read_log()}"
        time.sleep(0.2)
        assert os.path.isfile(record_file), "the client never contacted the WebSocket server"
        with open(record_file) as f:
            received = [json.loads(line) for line in f if line.strip()]
        assert received == dynamic, f"WebSocket server received {received}, expected {dynamic}"
    finally:
        mock.terminate()
        try:
            mock.wait(timeout=2)
        except subprocess.TimeoutExpired:
            mock.kill()
            mock.wait()

    # Independently exercise both runner branches with a long-lived script
    # that is valid under Python 2 and Python 3.
    with open(SERVER, "rb") as f:
        real_server = f.read()
    try:
        with open(SERVER, "wb") as f:
            f.write(b"import time\ntime.sleep(60)\n")

        stop_servers()
        run_start("--py3")
        procs = server_processes()
        assert procs and any("python3" in cmd for _, cmd in procs), \
            "--py3 branch did not leave math_server.py running under python3"

        stop_servers()
        run_start()
        procs = server_processes()
        assert procs and any("python2" in cmd for _, cmd in procs), \
            "default branch did not leave math_server.py running under python2"
    finally:
        stop_servers()
        with open(SERVER, "wb") as f:
            f.write(real_server)


if __name__ == "__main__":
    pytest.main([__file__])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
