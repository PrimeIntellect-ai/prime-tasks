#!/bin/bash
set +e
mkdir -p /logs/verifier
PROJECT=/home/user/telemetry_broker
failed=0

# Preserve the original final-state assertions and verify that pkg-config is
# actually used by active Makefile content.
python3 - <<'PY'
import os
import re

project = "/home/user/telemetry_broker"
log_path = os.path.join(project, "validation.log")
assert os.path.isfile(log_path), f"The validation log file {log_path} is missing. Did you run the test_runner.py script?"
with open(log_path, "r", encoding="utf-8") as f:
    content = f.read().strip()
assert "SUCCESS: All tests passed." in content, f"The validation log does not contain the expected success message. Found: {content}"

makefile_path = os.path.join(project, "Makefile")
assert os.path.isfile(makefile_path), "Makefile is missing"
with open(makefile_path, "r", encoding="utf-8") as f:
    active = "\n".join(line for line in f if not line.lstrip().startswith("#"))
assert re.search(r"pkg-config", active), "Makefile does not use pkg-config"
assert "libwebsockets" in active, "Makefile does not request libwebsockets through pkg-config"
assert "jansson" in active, "Makefile does not request jansson through pkg-config"
PY
if [ $? -ne 0 ]; then failed=1; fi

# Build from the submitted Makefile rather than trusting a pre-created executable.
(
    cd "$PROJECT" && make clean && make
)
if [ $? -ne 0 ]; then failed=1; fi

# Preserve the original executable assertions after rebuilding.
python3 - <<'PY'
import os
path = "/home/user/telemetry_broker/telemetry_broker"
assert os.path.isfile(path), f"The compiled executable {path} is missing. Did you run make?"
assert os.access(path, os.X_OK), f"The file {path} is not executable."
PY
if [ $? -ne 0 ]; then failed=1; fi

# Exercise the submitted C functions directly, including strict parsing and
# expiration of the rolling rate-limit window.
cat > /tmp/test_broker_functions.c <<'C_EOF'
#define main telemetry_broker_original_main
#include "/home/user/telemetry_broker/server.c"
#undef main

#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { fprintf(stderr, "check failed at line %d: %s\n", __LINE__, #x); return 1; } } while (0)

int main(void) {
    json_t *root = json_object();
    CHECK(root != NULL);
    CHECK(json_object_set_new(root, "metric", json_integer(10)) == 0);
    CHECK(json_object_set_new(root, "negative", json_integer(-3)) == 0);
    CHECK(json_object_set_new(root, "fraction", json_real(10.0)) == 0);
    CHECK(json_object_set_new(root, "text", json_string("10")) == 0);
    CHECK(json_object_set_new(root, "flag", json_true()) == 0);

    CHECK(evaluate_filter(root, "metric<11") == 1);
    CHECK(evaluate_filter(root, "metric<10") == 0);
    CHECK(evaluate_filter(root, "metric>9") == 1);
    CHECK(evaluate_filter(root, "metric>10") == 0);
    CHECK(evaluate_filter(root, "metric==10") == 1);
    CHECK(evaluate_filter(root, "metric==11") == 0);
    CHECK(evaluate_filter(root, "negative>-4") == 1);
    CHECK(evaluate_filter(root, "missing==10") == 0);
    CHECK(evaluate_filter(root, "fraction==10") == 0);
    CHECK(evaluate_filter(root, "text==10") == 0);
    CHECK(evaluate_filter(root, "flag==1") == 0);
    CHECK(evaluate_filter(root, "metric=10") == 0);
    CHECK(evaluate_filter(root, "metric===10") == 0);
    CHECK(evaluate_filter(root, "metric<10junk") == 0);
    CHECK(evaluate_filter(root, "<10") == 0);
    CHECK(evaluate_filter(root, "") == 0);
    json_decref(root);

    struct per_session_data pss;
    memset(&pss, 0, sizeof(pss));
    CHECK(check_rate_limit(&pss) == 1);
    CHECK(check_rate_limit(&pss) == 1);
    CHECK(check_rate_limit(&pss) == 1);
    CHECK(check_rate_limit(&pss) == 0);
    usleep(1100 * 1000);
    CHECK(check_rate_limit(&pss) == 1);
    return 0;
}
C_EOF
cc -Wall -Wextra -I"$PROJECT" /tmp/test_broker_functions.c -o /tmp/test_broker_functions $(pkg-config --cflags --libs libwebsockets jansson)
if [ $? -ne 0 ]; then
    failed=1
else
    /tmp/test_broker_functions
    if [ $? -ne 0 ]; then failed=1; fi
fi

# Execute the actual broker on unpredictable ports and filters, then validate
# WebSocket filtering, JSON handling, and per-connection rate limiting.
python3 - <<'PY'
import asyncio
import json
import os
import random
import socket
import string
import subprocess
import time

import websockets

BROKER = "/home/user/telemetry_broker/telemetry_broker"

def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]

def random_key():
    return "metric_" + "".join(random.choice(string.ascii_lowercase) for _ in range(12))

async def connect_with_retry(port, proc):
    last = None
    for _ in range(40):
        if proc.poll() is not None:
            raise AssertionError(f"broker exited during startup with status {proc.returncode}")
        try:
            return await websockets.connect(f"ws://127.0.0.1:{port}")
        except Exception as exc:
            last = exc
            await asyncio.sleep(0.05)
    raise AssertionError(f"could not connect to broker: {last}")

async def exchange(ws, payload):
    await ws.send(payload if isinstance(payload, str) else json.dumps(payload))
    return await asyncio.wait_for(ws.recv(), timeout=2.0)

async def run_case(op):
    key = random_key()
    pivot = random.randint(1000, 9000)
    port = free_port()
    proc = subprocess.Popen(
        [BROKER, str(port), f"{key}{op}{pivot}"],
        cwd=os.path.dirname(BROKER),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        ws = await connect_with_retry(port, proc)
        async with ws:
            accepted = pivot - 1 if op == "<" else pivot + 1 if op == ">" else pivot
            rejected = pivot if op in ("<", ">") else pivot + 1
            assert await exchange(ws, {key: accepted}) == "ACCEPTED"
            assert await exchange(ws, {key: rejected}) == "REJECTED"
            assert await exchange(ws, {"unrelated": accepted}) == "REJECTED"

        ws = await connect_with_retry(port, proc)
        async with ws:
            assert await exchange(ws, "{") == "INVALID_JSON"

        if op == "<":
            ws = await connect_with_retry(port, proc)
            async with ws:
                replies = [await exchange(ws, {key: pivot - 1}) for _ in range(4)]
                assert replies[:3] == ["ACCEPTED", "ACCEPTED", "ACCEPTED"], replies
                assert replies[3] == "RATE_LIMITED", replies
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)

async def main():
    for op in ("<", ">", "=="):
        await run_case(op)

asyncio.run(main())
PY
if [ $? -ne 0 ]; then failed=1; fi

if [ "$failed" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
