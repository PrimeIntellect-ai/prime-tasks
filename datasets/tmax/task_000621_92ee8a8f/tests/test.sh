#!/bin/bash
mkdir -p /logs/verifier

# The instructed server stays alive after serving a client, so stop any copy the
# agent may have left running before binding the verification server to port 8080.
pkill -f '/home/user/mock_ci_server.py' 2>/dev/null || true

if cd /home/user/ci_aggregator \
   && cargo clean >/dev/null 2>&1 \
   && timeout 240s cargo build --release \
   && python3 - <<'PY'
import ast
import json
import os
import secrets
import subprocess
import sys
import tempfile
import time

PROJECT = "/home/user/ci_aggregator"
BINARY = os.path.join(PROJECT, "target", "release", "ci_aggregator")
OUTPUT = "/home/user/final_cost.txt"
MOCK = "/home/user/mock_ci_server.py"

assert os.path.isfile(os.path.join(PROJECT, "src", "main.rs")), "src/main.rs is missing"
assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Cargo.toml is missing"
assert os.path.isfile(BINARY), "The ci_aggregator executable was not built"
assert os.access(BINARY, os.X_OK), "The built ci_aggregator is not executable"
assert os.path.isfile(MOCK), f"{MOCK} is missing"


def extract_original_events():
    with open(MOCK, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read())
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == "events":
                    events = ast.literal_eval(node.value)
                    assert isinstance(events, list)
                    return events
    raise AssertionError("Could not find 'events' list in mock_ci_server.py")


def expected_cost(events):
    states = ["START", "BUILD", "TEST", "DEPLOY", "END"]
    state_idx = 0
    last_accepted = None
    total = 0.0
    for ev in events:
        name = ev["event"]
        cost = ev["compute_cost"]
        timestamp = ev["timestamp_ms"]
        if last_accepted is not None and timestamp - last_accepted <= 50:
            continue
        if name == states[state_idx]:
            total += cost
            last_accepted = timestamp
            state_idx = (state_idx + 1) % len(states)
    return f"{total:.2f}"


SERVER_SOURCE = r'''
import asyncio
import json
import os
import sys
import websockets

fixture_path, ready_path = sys.argv[1], sys.argv[2]
with open(fixture_path, "r", encoding="utf-8") as f:
    events = json.load(f)
finished = asyncio.Event()

async def handler(websocket, *args):
    try:
        for event in events:
            await websocket.send(json.dumps(event))
            await asyncio.sleep(0.003)
    finally:
        finished.set()

async def main():
    async with websockets.serve(handler, "127.0.0.1", 8080):
        with open(ready_path, "w", encoding="utf-8") as f:
            f.write("ready")
        await finished.wait()

asyncio.run(main())
'''


def run_case(name, events):
    with tempfile.TemporaryDirectory(prefix="ci_verify_") as td:
        fixture = os.path.join(td, "events.json")
        ready = os.path.join(td, "ready")
        server_script = os.path.join(td, "server.py")
        server_log = os.path.join(td, "server.log")
        with open(fixture, "w", encoding="utf-8") as f:
            json.dump(events, f)
        with open(server_script, "w", encoding="utf-8") as f:
            f.write(SERVER_SOURCE)

        try:
            os.remove(OUTPUT)
        except FileNotFoundError:
            pass

        with open(server_log, "w+", encoding="utf-8") as log:
            server = subprocess.Popen(
                [sys.executable, server_script, fixture, ready],
                stdout=log,
                stderr=log,
            )
            try:
                deadline = time.time() + 8
                while not os.path.exists(ready):
                    if server.poll() is not None:
                        log.seek(0)
                        raise AssertionError(f"Verification WebSocket server failed: {log.read()}")
                    if time.time() >= deadline:
                        raise AssertionError("Timed out starting verification WebSocket server")
                    time.sleep(0.02)

                result = subprocess.run(
                    [BINARY],
                    cwd=PROJECT,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=15,
                )
                assert result.returncode == 0, (
                    f"Aggregator did not exit cleanly for {name} (code {result.returncode}). "
                    f"stdout={result.stdout!r}, stderr={result.stderr!r}"
                )
                server.wait(timeout=8)
            finally:
                if server.poll() is None:
                    server.terminate()
                    try:
                        server.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        server.kill()
                        server.wait()

        # Preserve the original verifier's output-file and derived-value assertions.
        assert os.path.isfile(OUTPUT), f"{OUTPUT} was not created for {name}"
        with open(OUTPUT, "r", encoding="utf-8") as f:
            actual = f.read().strip()
        wanted = expected_cost(events)
        assert actual == wanted, (
            f"Incorrect cost for {name}: expected {wanted!r}, found {actual!r}"
        )


# First exercise the exact fixture exposed by the instructed mock server.
run_case("original mock fixture", extract_original_events())

# Use unpredictable exactly representable costs so a fixed final_cost.txt cannot pass.
rng = secrets.SystemRandom()
def cost():
    return rng.randint(1, 160) / 4.0

boundary_case = [
    {"event": "START",  "compute_cost": cost(), "timestamp_ms": 1000},
    {"event": "TEST",   "compute_cost": cost(), "timestamp_ms": 1060},  # out of order
    {"event": "BUILD",  "compute_cost": cost(), "timestamp_ms": 1070},
    {"event": "TEST",   "compute_cost": cost(), "timestamp_ms": 1120},  # exactly 50ms
    {"event": "TEST",   "compute_cost": cost(), "timestamp_ms": 1121},
    {"event": "DEPLOY", "compute_cost": cost(), "timestamp_ms": 1150},  # rate limited
    {"event": "DEPLOY", "compute_cost": cost(), "timestamp_ms": 1180},
    {"event": "END",    "compute_cost": cost(), "timestamp_ms": 1230},  # exactly 50ms
    {"event": "END",    "compute_cost": cost(), "timestamp_ms": 1231},
    {"event": "START",  "compute_cost": cost(), "timestamp_ms": 1290},
]
run_case("rate-limit boundaries and state reset", boundary_case)

accepted_only_case = [
    {"event": "START",  "compute_cost": cost(), "timestamp_ms": 2000},
    {"event": "BUILD",  "compute_cost": cost(), "timestamp_ms": 2020},  # rate limited
    {"event": "TEST",   "compute_cost": cost(), "timestamp_ms": 2080},  # out of order
    {"event": "BUILD",  "compute_cost": cost(), "timestamp_ms": 2081},  # measured from START
    {"event": "TEST",   "compute_cost": cost(), "timestamp_ms": 2100},  # rate limited
    {"event": "TEST",   "compute_cost": cost(), "timestamp_ms": 2132},
    {"event": "DEPLOY", "compute_cost": cost(), "timestamp_ms": 2192},
    {"event": "END",    "compute_cost": cost(), "timestamp_ms": 2252},
    {"event": "START",  "compute_cost": cost(), "timestamp_ms": 2312},
    {"event": "BUILD",  "compute_cost": cost(), "timestamp_ms": 2372},
]
run_case("accepted-message timing and incomplete runs", accepted_only_case)
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
