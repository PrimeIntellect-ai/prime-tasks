#!/bin/bash
set -u
mkdir -p /logs/verifier

cat <<'VERIFY_EOF' > /tmp/run_verification.sh
#!/bin/bash
set -euo pipefail

cat <<'PY_EOF' > /tmp/test_initial_state.py
import json
import os
import socket


def test_results_json():
    results_path = "/home/user/results.json"
    assert os.path.isfile(results_path), f"The file {results_path} does not exist."
    with open(results_path, "r") as f:
        results = json.load(f)

    expected = {"python": 40, "ruby": True, "node": 9}
    assert results == expected, f"Expected {expected}, but got {results}."
    assert type(results["python"]) is int
    assert type(results["ruby"]) is bool
    assert type(results["node"]) is int


def test_run_tests_script_exists():
    assert os.path.isfile("/home/user/run_tests.py")


def test_server_source_exists():
    assert os.path.isfile("/home/user/app/server.js")


def test_server_listening():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1.0)
        assert s.connect_ex(("127.0.0.1", 8080)) == 0, \
            "The server is not listening on port 8080."
PY_EOF
python3 -m pytest /tmp/test_initial_state.py -x --tb=short

# Stop whichever process currently owns port 8080 so that run_tests.py can be
# observed against a controlled WebSocket endpoint, then server.js can itself
# be launched and tested.
cat <<'PY_EOF' > /tmp/kill_port_8080.py
import os
import signal
import time

inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) > 9 and fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                    inodes.add(fields[9])
    except FileNotFoundError:
        pass

pids = set()
for name in os.listdir("/proc"):
    if not name.isdigit() or name == "1":
        continue
    fd_dir = f"/proc/{name}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                pids.add(int(name))
                break
    except (FileNotFoundError, PermissionError):
        pass

for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
time.sleep(0.5)
for pid in pids:
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
PY_EOF
python3 /tmp/kill_port_8080.py

# Controlled endpoint proving that run_tests.py actually opens all three
# required WebSocket routes and sends the required expressions.
cat <<'PY_EOF' > /tmp/probe_server.py
import asyncio
import json
import websockets

records = []
expected = {
    ("/eval/python", "max(10, 20) * 2"): 40,
    ("/eval/ruby", "15 % 4 == 3"): True,
    ("/eval/node", "Math.pow(2, 3) + 1"): 9,
}

async def handler(ws, *args):
    if args:
        path = args[0]
       elif hasattr(ws, "request"):
        path = ws.request.path
    else:
        path = ws.path
    async for raw in ws:
        try:
            expr = json.loads(raw)["expr"]
            key = (path, expr)
            records.append([path, expr])
            with open("/tmp/probe_records.json", "w") as f:
                json.dump(records, f)
            if key not in expected:
                await ws.send(json.dumps({"error": "unexpected request"}))
            else:
                await ws.send(json.dumps({"result": expected[key]}))
        except Exception as exc:
            await ws.send(json.dumps({"error": str(exc)}))

async def main():
    async with websockets.serve(handler, "127.0.0.1", 8080):
        with open("/tmp/probe_ready", "w") as f:
            f.write("ready")
        await asyncio.Future()

asyncio.run(main())
PY_EOF
rm -f /tmp/probe_ready /tmp/probe_records.json /home/user/results.json
python3 /tmp/probe_server.py >/tmp/probe_server.log 2>&1 &
PROBE_PID=$!
trap 'kill "$PROBE_PID" 2>/dev/null || true' EXIT
for i in $(seq 1 50); do
    [ -f /tmp/probe_ready ] && break
    kill -0 "$PROBE_PID" 2>/dev/null || { cat /tmp/probe_server.log; exit 1; }
    sleep 0.1
done
[ -f /tmp/probe_ready ]
timeout 20s python3 /home/user/run_tests.py

cat <<'PY_EOF' > /tmp/test_client_artifacts.py
import json
import os


def test_run_tests_requests_and_output():
    required = {
        ("/eval/python", "max(10, 20) * 2"),
        ("/eval/ruby", "15 % 4 == 3"),
        ("/eval/node", "Math.pow(2, 3) + 1"),
    }
    assert os.path.isfile("/tmp/probe_records.json")
    with open("/tmp/probe_records.json") as f:
        observed = {tuple(item) for item in json.load(f)}
    assert required <= observed, f"run_tests.py did not make all required requests: {observed}"

    with open("/home/user/results.json") as f:
        results = json.load(f)
    assert results == {"python": 40, "ruby": True, "node": 9}
    assert type(results["python"]) is int
    assert type(results["ruby"]) is bool
    assert type(results["node"]) is int
PY_EOF
python3 -m pytest /tmp/test_client_artifacts.py -x --tb=short
kill "$PROBE_PID"
wait "$PROBE_PID" 2>/dev/null || true
trap - EXIT

# Execute the submitted server.js itself, rather than trusting an arbitrary
# listener that the agent left on the port.
cd /home/user/app
nohup node server.js >/tmp/submitted_server.log 2>&1 </dev/null &
SERVER_PID=$!
cd /
for i in $(seq 1 50); do
    if python3 - <<'PY_EOF'
import socket
s = socket.socket()
s.settimeout(0.1)
try:
    s.connect(("127.0.0.1", 8080))
except OSError:
    raise SystemExit(1)
finally:
    s.close()
PY_EOF
    then
        break
    fi
    kill -0 "$SERVER_PID" 2>/dev/null || { cat /tmp/submitted_server.log; exit 1; }
    sleep 0.1
done
kill -0 "$SERVER_PID"

cat <<'PY_EOF' > /tmp/test_websocket_server.py
import asyncio
import json
import pytest
import websockets


async def roundtrip(language, expr):
    async with websockets.connect(
        f"ws://127.0.0.1:8080/eval/{language}",
        open_timeout=2,
        close_timeout=1,
    ) as ws:
        await ws.send(json.dumps({"expr": expr}))
        return json.loads(await asyncio.wait_for(ws.recv(), timeout=4))


def test_python_evaluation_and_native_types():
    result = asyncio.run(roundtrip("python", "min(9, 4) + 6"))
    assert result == {"result": 10}
    assert type(result["result"]) is int

    result = asyncio.run(roundtrip("python", "max(3, 8) == 8"))
    assert result == {"result": True}
    assert type(result["result"]) is bool


def test_ruby_evaluation_and_native_types():
    result = asyncio.run(roundtrip("ruby", "(7 * 6) - 2"))
    assert result == {"result": 40}
    assert type(result["result"]) is int

    result = asyncio.run(roundtrip("ruby", "10 > 3 && 2 == 2"))
    assert result == {"result": True}
    assert type(result["result"]) is bool


def test_node_evaluation_and_native_types():
    result = asyncio.run(roundtrip("node", "Math.sqrt(81) + 2"))
    assert result == {"result": 11}
    assert type(result["result"]) is int

    result = asyncio.run(roundtrip("node", "false || (5 === 5)"))
    assert result == {"result": True}
    assert type(result["result"]) is bool


async def assert_rejected(path):
    try:
        ws = await websockets.connect(
            f"ws://127.0.0.1:8080{path}",
            open_timeout=2,
            close_timeout=0.2,
        )
    except Exception:
        return
    try:
        await ws.close()
    finally:
        pytest.fail(f"WebSocket upgrade was accepted for invalid route {path!r}")


@pytest.mark.parametrize("path", [
    "/",
    "/eval/php",
    "/eval/python/",
    "/foo/eval/python",
    "/eval/node/extra",
])
def test_invalid_routes_are_rejected(path):
    asyncio.run(assert_rejected(path))
PY_EOF
python3 -m pytest /tmp/test_websocket_server.py -x --tb=short
VERIFY_EOF
chmod +x /tmp/run_verification.sh

if /tmp/run_verification.sh 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
