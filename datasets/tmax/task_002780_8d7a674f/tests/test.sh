#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import json
import os
import random
import signal
import subprocess
import sys
import time
import importlib.util

import websockets

CI = "/home/user/ci_env"
CONF = f"{CI}/nginx.conf"
EMULATOR = f"{CI}/emulator.py"
BENCHMARK = f"{CI}/benchmark.py"
REPORT = f"{CI}/benchmark_report.json"


def stop_existing_services():
    subprocess.run(["nginx", "-s", "stop", "-c", CONF], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["pkill", "-f", "/home/user/ci_env/emulator.py"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["pkill", "-x", "nginx"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.2)


def terminate_process(proc):
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=3)


def socket_is_owned_by_nginx(source_port):
    inode = None
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_port = int(fields[1].split(":")[1], 16)
                    remote_port = int(fields[2].split(":")[1], 16)
                    if local_port == source_port and remote_port == 9000:
                        inode = fields[9]
                        break
        except OSError:
            pass
        if inode:
            break
    if not inode:
        return False

    target = f"socket:[{inode}]"
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/comm") as f:
                if f.read().strip() != "nginx":
                    continue
            for fd in os.listdir(f"/proc/{pid}/fd"):
                try:
                    if os.readlink(f"/proc/{pid}/fd/{fd}") == target:
                        return True
                except OSError:
                    pass
        except OSError:
            pass
    return False


async def wait_for_proxy():
    deadline = time.monotonic() + 8
    last_error = None
    while time.monotonic() < deadline:
        try:
            ws = await websockets.connect("ws://127.0.0.1:8080", open_timeout=1)
            return ws
        except Exception as exc:
            last_error = exc
            await asyncio.sleep(0.1)
    raise AssertionError(f"WebSocket proxy did not become ready: {last_error}")


def random_valid_case(rng):
    tokens = []
    stack = []
    for _ in range(rng.randint(8, 20)):
        if len(stack) < 2 or rng.random() < 0.58:
            value = rng.randint(-100000, 100000)
            tokens.extend(["PUSH", str(value)])
            stack.append(value)
        else:
            op = rng.choice(["ADD", "MUL"])
            b = stack.pop()
            a = stack.pop()
            stack.append(a + b if op == "ADD" else a * b)
            tokens.append(op)
    return " ".join(tokens), str(stack[-1])


async def exercise_real_emulator():
    rng = random.SystemRandom()
    ws = await wait_for_proxy()
    try:
        cases = [random_valid_case(rng) for _ in range(35)]
        cases.extend([
            ("ADD", "ERROR"),
            ("MUL", "ERROR"),
            (f"PUSH {rng.randint(1, 9999)} ADD", "ERROR"),
            (f"PUSH {rng.randint(1, 9999)} MUL", "ERROR"),
            (f"PUSH not_an_integer_{rng.randint(1, 999999)}", "ERROR"),
            (f"PUSH {rng.randint(1, 9999)} UNKNOWN_{rng.randint(1, 999999)}", "ERROR"),
            ("", "ERROR"),
        ])
        rng.shuffle(cases)
        for command, expected in cases:
            await ws.send(command)
            actual = await asyncio.wait_for(ws.recv(), timeout=2)
            assert actual == expected, f"WebSocket emulator returned {actual!r} for {command!r}; expected {expected!r}"
    finally:
        await ws.close()


async def run_instrumented_benchmark():
    expected_payload = "PUSH 5 PUSH 10 ADD PUSH 2 MUL"
    observations = []
    first_received = None
    last_sent = None

    async def handler(websocket):
        nonlocal first_received, last_sent
        peer = websocket.remote_address
        source_port = peer[1]
        proxied = socket_is_owned_by_nginx(source_port)
        async for message in websocket:
            now = time.monotonic()
            if first_received is None:
                first_received = now
            observations.append((message, proxied))
            await asyncio.sleep(0.01)
            await websocket.send("30" if message == expected_payload else "ERROR")
            last_sent = time.monotonic()

    if os.path.exists(REPORT):
        os.unlink(REPORT)

    async with websockets.serve(handler, "127.0.0.1", 9000):
        started = time.monotonic()
        proc = await asyncio.create_subprocess_exec(
            sys.executable, BENCHMARK,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=20)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.wait()
            raise AssertionError("benchmark.py timed out")
        elapsed_ms = (time.monotonic() - started) * 1000

    assert proc.returncode == 0, (
        f"benchmark.py exited with {proc.returncode}\nstdout: {stdout.decode(errors='replace')}"
        f"\nstderr: {stderr.decode(errors='replace')}"
    )
    assert len(observations) == 100, f"benchmark.py sent {len(observations)} messages instead of exactly 100"
    assert all(message == expected_payload for message, _ in observations), \
        "benchmark.py sent a payload other than the required stack-machine command"
    assert all(proxied for _, proxied in observations), \
        "benchmark.py did not send every request through the Nginx reverse proxy on port 8080"
    assert first_received is not None and last_sent is not None

    assert os.path.isfile(REPORT), "benchmark.py did not create benchmark_report.json"
    with open(REPORT) as f:
        data = json.load(f)
    assert set(data) == {"successful_requests", "total_time_ms"}, "Benchmark report has an incorrect format"
    assert data["successful_requests"] == 100
    assert isinstance(data["total_time_ms"], (int, float)) and not isinstance(data["total_time_ms"], bool)
    assert data["total_time_ms"] > 0
    network_ms = (last_sent - first_received) * 1000
    assert data["total_time_ms"] + 150 >= network_ms, \
        "Reported total_time_ms is too small to be a measurement of the requests"
    assert data["total_time_ms"] <= elapsed_ms + 500, \
        "Reported total_time_ms is not consistent with the executed benchmark"


def test_00_execute_websocket_integration_and_benchmark():
    assert os.path.isfile(EMULATOR), f"File {EMULATOR} does not exist."
    assert os.path.isfile(BENCHMARK), f"File {BENCHMARK} does not exist."
    assert os.path.isfile(CONF), f"File {CONF} does not exist."

    syntax = subprocess.run(["nginx", "-t", "-c", CONF], capture_output=True, text=True)
    assert syntax.returncode == 0, f"nginx.conf is invalid: {syntax.stderr}"

    stop_existing_services()
    emulator_proc = None
    nginx_proc = None
    try:
        emulator_proc = subprocess.Popen([sys.executable, EMULATOR], stdout=subprocess.DEVNULL,
                                         stderr=subprocess.DEVNULL)
        nginx_proc = subprocess.Popen(["nginx", "-c", CONF], stdout=subprocess.DEVNULL,
                                      stderr=subprocess.DEVNULL)
        asyncio.run(exercise_real_emulator())

        terminate_process(emulator_proc)
        emulator_proc = None
        asyncio.run(run_instrumented_benchmark())
    finally:
        terminate_process(emulator_proc)
        subprocess.run(["nginx", "-s", "stop", "-c", CONF], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, check=False)
        terminate_process(nginx_proc)
        subprocess.run(["pkill", "-x", "nginx"], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, check=False)


def test_benchmark_report_exists_and_valid():
    report_path = "/home/user/ci_env/benchmark_report.json"
    assert os.path.isfile(report_path), f"Benchmark report {report_path} was not created."

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "benchmark_report.json is not valid JSON."

    assert "successful_requests" in data, "Missing 'successful_requests' in benchmark report."
    assert data["successful_requests"] == 100, f"Expected 100 successful_requests, got {data['successful_requests']}."

    assert "total_time_ms" in data, "Missing 'total_time_ms' in benchmark report."
    assert isinstance(data["total_time_ms"], (int, float)), "'total_time_ms' must be a number."
    assert data["total_time_ms"] > 0, "'total_time_ms' must be greater than 0."


def test_nginx_config_websocket_upgrade():
    conf_path = "/home/user/ci_env/nginx.conf"
    assert os.path.isfile(conf_path), f"File {conf_path} does not exist."

    with open(conf_path, "r") as f:
        content = f.read()

    assert "proxy_set_header Upgrade $http_upgrade;" in content or "proxy_set_header Upgrade $http_upgrade" in content, \
        "nginx.conf is missing the 'proxy_set_header Upgrade $http_upgrade;' directive."
    assert "proxy_set_header Connection" in content, \
        "nginx.conf is missing the 'proxy_set_header Connection' directive."


def test_emulator_stack_machine_logic():
    emulator_path = "/home/user/ci_env/emulator.py"
    assert os.path.isfile(emulator_path), f"File {emulator_path} does not exist."

    spec = importlib.util.spec_from_file_location("emulator", emulator_path)
    emulator = importlib.util.module_from_spec(spec)
    sys.modules["emulator"] = emulator
    try:
        spec.loader.exec_module(emulator)
    except Exception as e:
        assert False, f"Failed to import emulator.py: {e}"

    assert hasattr(emulator, "process_command"), "emulator.py is missing 'process_command' function."

    assert emulator.process_command("PUSH 5 PUSH 10 ADD PUSH 2 MUL") == "30", \
        "process_command failed on 'PUSH 5 PUSH 10 ADD PUSH 2 MUL'."
    assert emulator.process_command("PUSH 42") == "42", \
        "process_command failed on 'PUSH 42'."
    assert emulator.process_command("PUSH 2 PUSH 3 PUSH 4 MUL ADD") == "14", \
        "process_command failed on 'PUSH 2 PUSH 3 PUSH 4 MUL ADD'."

    assert emulator.process_command("ADD") == "ERROR", \
        "process_command should return 'ERROR' for invalid stack operations (e.g., empty stack ADD)."
    assert emulator.process_command("PUSH 1 ADD") == "ERROR", \
        "process_command should return 'ERROR' for invalid stack operations (e.g., not enough elements for ADD)."
    assert emulator.process_command("PUSH A") == "ERROR" or emulator.process_command("PUSH A") == "ERROR", \
        "process_command should handle invalid integers gracefully."

    rng = random.SystemRandom()
    for _ in range(50):
        command, expected = random_valid_case(rng)
        assert emulator.process_command(command) == expected, \
            f"process_command failed generated case {command!r}"
    for command in (
        f"PUSH bad_{rng.randint(1, 10**9)}",
        f"PUSH {rng.randint(-9999, 9999)} ADD",
        f"PUSH {rng.randint(-9999, 9999)} MUL",
        f"PUSH {rng.randint(-9999, 9999)} BAD_{rng.randint(1, 10**9)}",
        "",
    ):
        assert emulator.process_command(command) == "ERROR", \
            f"process_command should reject malformed command {command!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
