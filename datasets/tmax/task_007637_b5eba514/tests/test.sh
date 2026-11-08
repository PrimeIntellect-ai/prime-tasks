#!/bin/bash
mkdir -p /logs/verifier
pkill -f '/home/user/ws_server.py' 2>/dev/null || true
sleep 0.5

cat <<'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import heapq
import json
import os
import pwd
import secrets
import stat

import websockets

PIPELINE_PATH = "/home/user/pipeline.json"
ANALYZER_PATH = "/home/user/analyze.py"
LOG_PATH = "/home/user/ws_received.log"

ORIGINAL_PIPELINE = '''{
  "link_binary": {
    "deps": ["compile_c", "compile_ui"],
    "expr": "DIV MUL 100 2 5"
  },
  "compile_c": {
    "deps": ["fetch_deps"],
    "expr": "ADD XOR 15 7 2"
  },
  "compile_ui": {
    "deps": ["fetch_deps", "generate_assets"],
    "expr": "SUB 50 MUL 4 5"
  },
  "fetch_deps": {
    "deps": [],
    "expr": "ADD 10 15"
  },
  "generate_assets": {
    "deps": [],
    "expr": "XOR 255 170"
  },
  "package_apk": {
    "deps": ["link_binary"],
    "expr": "MUL ADD 2 3 SUB 10 2"
  }
}
'''


def evaluate_prefix(expr):
    tokens = expr.strip().split()
    stack = []
    for token in reversed(tokens):
        if token in ['ADD', 'SUB', 'MUL', 'DIV', 'XOR']:
            if len(stack) < 2:
                raise ValueError("Invalid prefix expression")
            op1 = stack.pop()
            op2 = stack.pop()
            if token == 'ADD':
                stack.append(op1 + op2)
            elif token == 'SUB':
                stack.append(op1 - op2)
            elif token == 'MUL':
                stack.append(op1 * op2)
            elif token == 'DIV':
                stack.append(op1 // op2)
            elif token == 'XOR':
                stack.append(op1 ^ op2)
        else:
            stack.append(int(token))
    if len(stack) != 1:
        raise ValueError("Invalid prefix expression")
    return stack[0]


def get_expected_results(pipeline_path):
    with open(pipeline_path, 'r') as f:
        data = json.load(f)

    in_degree = {k: 0 for k in data}
    adj = {k: [] for k in data}

    for k, v in data.items():
        for dep in v.get('deps', []):
            if dep in adj:
                adj[dep].append(k)
                in_degree[k] += 1

    pq = []
    for k, deg in in_degree.items():
        if deg == 0:
            heapq.heappush(pq, k)

    results = []
    while pq:
        curr = heapq.heappop(pq)
        val = evaluate_prefix(data[curr]['expr'])
        results.append({"step": curr, "result": val})

        for neighbor in adj[curr]:
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                heapq.heappush(pq, neighbor)

    return results


def parse_messages(lines):
    actual_results = []
    for line in lines:
        try:
            actual_results.append(json.loads(line))
        except json.JSONDecodeError:
            assert False, f"Log file contains invalid JSON: {line}"
    return actual_results


def assert_results(actual_results, expected_results, source):
    assert len(actual_results) == len(expected_results), (
        f"Expected {len(expected_results)} messages, but found {len(actual_results)} in {source}. "
        f"Ensure all steps are processed."
    )
    for i, (act, exp) in enumerate(zip(actual_results, expected_results)):
        assert act == exp, (
            f"Message mismatch at step {i + 1} (0-indexed {i}).\n"
            f"Expected: {exp}\n"
            f"Actual:   {act}\n"
            f"Check your topological sort logic and expression evaluator."
        )


async def execute_and_capture():
    received = []
    close_codes = []
    connected = asyncio.Event()
    closed = asyncio.Event()

    async def handler(websocket, *args):
        connected.set()
        try:
            async for message in websocket:
                received.append(message)
        finally:
            close_codes.append(websocket.close_code)
            closed.set()

    user = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    async with websockets.serve(handler, "localhost", 9999):
        proc = await asyncio.create_subprocess_exec(
            "python3", ANALYZER_PATH,
            cwd="/home/user",
            env={**os.environ, "HOME": "/home/user", "USER": "user"},
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            preexec_fn=demote,
        )
        try:
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=20)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.wait()
            raise AssertionError("analyze.py did not finish within 20 seconds")

        assert proc.returncode == 0, (
            f"analyze.py exited with status {proc.returncode}.\n"
            f"stdout: {stdout.decode(errors='replace')}\n"
            f"stderr: {stderr.decode(errors='replace')}"
        )
        try:
            await asyncio.wait_for(connected.wait(), timeout=2)
            await asyncio.wait_for(closed.wait(), timeout=2)
        except asyncio.TimeoutError:
            raise AssertionError("analyze.py did not establish and cleanly close its WebSocket connection")

    assert close_codes and all(code in (1000, 1001) for code in close_codes), (
        f"WebSocket connection was not cleanly closed: {close_codes}"
    )
    return received


def make_dynamic_pipeline():
    names = [f"step_{secrets.token_hex(4)}" for _ in range(6)]
    a, b, c, d, e, f = names
    x = secrets.randbelow(80) + 11
    y = secrets.randbelow(30) + 2
    z = secrets.randbelow(20) + 2
    return {
        a: {"deps": [], "expr": f"ADD {x} {y}"},
        b: {"deps": [], "expr": f"XOR {x + 17} {z}"},
        c: {"deps": [a], "expr": f"SUB MUL {y} {z} {x}"},
        d: {"deps": [a, b], "expr": f"DIV MUL {x} {z} {z}"},
        e: {"deps": [b], "expr": f"MUL ADD {y} {z} SUB {x} {y}"},
        f: {"deps": [c, d, e], "expr": f"ADD XOR {x} {y} DIV {x * z} {z}"},
    }


def test_websocket_log_correct():
    assert os.path.exists(PIPELINE_PATH), f"Pipeline file {PIPELINE_PATH} is missing."
    with open(PIPELINE_PATH, "r") as f:
        assert f.read() == ORIGINAL_PIPELINE, "pipeline.json was modified from the supplied fixture."

    assert os.path.exists(ANALYZER_PATH), f"Analyzer file {ANALYZER_PATH} is missing."
    analyzer_stat = os.lstat(ANALYZER_PATH)
    assert stat.S_ISREG(analyzer_stat.st_mode), f"{ANALYZER_PATH} must be a regular file."

    original_messages = []
    try:
        if os.path.lexists(LOG_PATH):
            os.unlink(LOG_PATH)

        expected_results = get_expected_results(PIPELINE_PATH)
        original_messages = asyncio.run(execute_and_capture())
        actual_results = parse_messages(original_messages)
        assert_results(actual_results, expected_results, "captured WebSocket traffic")

        with open(PIPELINE_PATH, "r") as f:
            assert f.read() == ORIGINAL_PIPELINE, "analyze.py modified pipeline.json while running."

        with open(LOG_PATH, "w") as f:
            for message in original_messages:
                f.write(message + "\n")

        assert os.path.exists(LOG_PATH), (
            f"Log file {LOG_PATH} was not created. The script may not have run or sent messages correctly."
        )
        with open(LOG_PATH, 'r') as f:
            lines = [line.strip() for line in f if line.strip()]
        logged_results = parse_messages(lines)
        assert_results(logged_results, expected_results, LOG_PATH)

        dynamic_pipeline = make_dynamic_pipeline()
        dynamic_text = json.dumps(dynamic_pipeline, indent=2, sort_keys=False) + "\n"
        with open(PIPELINE_PATH, "w") as f:
            f.write(dynamic_text)
        os.chmod(PIPELINE_PATH, 0o666)

        dynamic_expected = get_expected_results(PIPELINE_PATH)
        dynamic_messages = asyncio.run(execute_and_capture())
        dynamic_actual = parse_messages(dynamic_messages)
        assert_results(dynamic_actual, dynamic_expected, "dynamic captured WebSocket traffic")

        with open(PIPELINE_PATH, "r") as f:
            assert f.read() == dynamic_text, "analyze.py modified the dynamic pipeline fixture."
    finally:
        with open(PIPELINE_PATH, "w") as f:
            f.write(ORIGINAL_PIPELINE)
        os.chmod(PIPELINE_PATH, 0o777)
        if original_messages:
            with open(LOG_PATH, "w") as f:
                for message in original_messages:
                    f.write(message + "\n")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
