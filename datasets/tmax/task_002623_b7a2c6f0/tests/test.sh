#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import os
import secrets
import shutil
import subprocess
import time

import pytest
import websockets

URI = "ws://127.0.0.1:9090"


def reset_runtime_state():
    for path in ("/tmp/last_build_time", "/home/user/ci_states.log", "/home/user/config_merged.env"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def write_config(path, entries):
    with open(path, "w") as f:
        for key, value in entries:
            f.write(f"{key}={value}\n")


async def recv_line(ws, timeout=4):
    value = await asyncio.wait_for(ws.recv(), timeout=timeout)
    assert isinstance(value, str)
    return value.strip()


async def wait_for_log_entry(entry, timeout=2.5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with open("/home/user/ci_states.log") as f:
                lines = [line.strip() for line in f if line.strip()]
        except FileNotFoundError:
            lines = []
        if entry in lines:
            return time.monotonic(), lines
        await asyncio.sleep(0.03)
    pytest.fail(f"Timed out waiting for log entry {entry!r}")


def setup_module(module):
    reset_runtime_state()
    write_config("/home/user/config_base.env", [
        ("APP_VERSION", "1.0.0"),
        ("BUILD_THREADS", "4"),
        ("DEBUG", "false"),
        ("PLATFORM", "android"),
    ])
    write_config("/home/user/config_override.env", [
        ("DEBUG", "true"),
        ("SIGNING_KEY", "prod.keystore"),
        ("APP_VERSION", "1.0.1"),
    ])


def test_scripts_exist_and_executable():
    assert os.path.isfile('/home/user/ci_backend.sh'), "/home/user/ci_backend.sh does not exist"
    assert os.access('/home/user/ci_backend.sh', os.X_OK), "/home/user/ci_backend.sh is not executable"
    assert os.path.isfile('/home/user/start_server.sh'), "/home/user/start_server.sh does not exist"
    assert os.access('/home/user/start_server.sh', os.X_OK), "/home/user/start_server.sh is not executable"
    assert shutil.which("websocat"), "websocat is not installed or not in PATH"
    assert shutil.which("bc"), "bc is not installed or not in PATH"
    subprocess.run(["websocat", "--version"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3)


def test_websocket_server_and_logic():
    async def run():
        async with websockets.connect(URI, open_timeout=3, close_timeout=1) as ws:
            await ws.send("BUILD AppOne 10+5")
            res1 = await recv_line(ws)
            assert res1 == "ACCEPTED AppOne 15", f"Expected 'ACCEPTED AppOne 15', got '{res1}'"

            await ws.send("BUILD AppTwo 2")
            res2 = await recv_line(ws)
            assert res2 == "RATE_LIMIT", f"Expected 'RATE_LIMIT', got '{res2}'"

            await asyncio.sleep(2.5)
            await ws.send("BUILD AppThree 2*3")
            res3 = await recv_line(ws)
            assert res3 == "ACCEPTED AppThree 6", f"Expected 'ACCEPTED AppThree 6', got '{res3}'"

    asyncio.run(run())


def test_ci_states_log():
    time.sleep(1.5)
    log_path = '/home/user/ci_states.log'
    assert os.path.isfile(log_path), f"{log_path} does not exist"
    with open(log_path) as f:
        content = f.read().strip()
    assert "[AppOne] INIT" in content, "[AppOne] INIT not found in ci_states.log"
    assert "[AppOne] SUCCESS" in content, "[AppOne] SUCCESS not found in ci_states.log"
    assert "[AppThree] INIT" in content, "[AppThree] INIT not found in ci_states.log"
    assert "[AppThree] SUCCESS" in content, "[AppThree] SUCCESS not found in ci_states.log"
    assert "[AppTwo]" not in content, "Rate-limited AppTwo should not appear in ci_states.log"


def test_config_merged_env():
    merged_path = '/home/user/config_merged.env'
    assert os.path.isfile(merged_path), f"{merged_path} does not exist"
    with open(merged_path) as f:
        merged_lines = [line.strip() for line in f if line.strip()]
    expected = [
        "APP_VERSION=1.0.1",
        "BUILD_THREADS=4",
        "DEBUG=true",
        "PLATFORM=android",
        "SIGNING_KEY=prod.keystore",
    ]
    assert merged_lines == expected, f"Merged config mismatch.\nExpected: {expected}\nGot: {merged_lines}"


def test_randomized_behavior_merging_state_and_global_rate_limit():
    async def run():
        reset_runtime_state()
        rng = secrets.SystemRandom()
        token = secrets.token_hex(5)
        accepted_one = f"DynA{token}"
        rejected = f"DynR{token}"
        accepted_two = f"DynB{token}"

        a, b, c, d = [rng.randint(3, 30) for _ in range(4)]
        expr_one = f"({a}+{b})*{c}-{d}"
        answer_one = (a + b) * c - d
        e, f, g = [rng.randint(4, 40) for _ in range(3)]
        expr_two = f"{e}*{f}+{g}"
        answer_two = e * f + g

        suffix = token.upper()
        base_one = [
            (f"ALPHA_{suffix}", secrets.token_hex(3)),
            (f"SHARED_{suffix}", "base_" + secrets.token_hex(3)),
            (f"OMEGA_{suffix}", str(rng.randint(100, 999))),
        ]
        override_one = [
            (f"SHARED_{suffix}", "override_" + secrets.token_hex(3)),
            (f"BETA_{suffix}", secrets.token_hex(4)),
        ]
        write_config('/home/user/config_base.env', base_one)
        write_config('/home/user/config_override.env', override_one)
        expected_one_map = dict(base_one)
        expected_one_map.update(dict(override_one))
        expected_one = [f"{k}={expected_one_map[k]}" for k in sorted(expected_one_map)]

        async with websockets.connect(URI, open_timeout=3, close_timeout=1) as ws_one:
            sent_at = time.monotonic()
            await ws_one.send(f"BUILD {accepted_one} {expr_one}")
            response = await recv_line(ws_one)
            reply_at = time.monotonic()
            assert response == f"ACCEPTED {accepted_one} {answer_one}"
            assert reply_at - sent_at < 1.0, "ACCEPTED response was not immediate"

            _, initial_lines = await wait_for_log_entry(f"[{accepted_one}] INIT", timeout=0.5)
            assert f"[{accepted_one}] SUCCESS" not in initial_lines, "SUCCESS was logged without the one-second build delay"
            assert os.path.isfile('/tmp/last_build_time'), "Accepted build did not create /tmp/last_build_time"

            # A different connection must share the same global rate limit.
            async with websockets.connect(URI, open_timeout=3, close_timeout=1) as ws_two:
                await ws_two.send(f"BUILD {rejected} {rng.randint(50, 90)}")
                limited = await recv_line(ws_two)
                assert limited == "RATE_LIMIT", f"Cross-connection request was not rate limited: {limited!r}"

            success_at, _ = await wait_for_log_entry(f"[{accepted_one}] SUCCESS")
            assert success_at - reply_at >= 0.75, "SUCCESS was logged too early"
            with open('/home/user/config_merged.env') as merged:
                actual_one = [line.strip() for line in merged if line.strip()]
            assert actual_one == expected_one, f"Dynamic merged config mismatch: {actual_one!r} != {expected_one!r}"

            base_two = [
                (f"DELTA_{suffix}", secrets.token_hex(4)),
                (f"REUSED_{suffix}", "old_" + secrets.token_hex(2)),
            ]
            override_two = [
                (f"GAMMA_{suffix}", str(rng.randint(1000, 9000))),
                (f"REUSED_{suffix}", "new_" + secrets.token_hex(2)),
            ]
            write_config('/home/user/config_base.env', base_two)
            write_config('/home/user/config_override.env', override_two)
            expected_two_map = dict(base_two)
            expected_two_map.update(dict(override_two))
            expected_two = [f"{k}={expected_two_map[k]}" for k in sorted(expected_two_map)]

            await asyncio.sleep(max(0, 2.3 - (time.monotonic() - sent_at)))
            await ws_one.send(f"BUILD {accepted_two} {expr_two}")
            response_two = await recv_line(ws_one)
            assert response_two == f"ACCEPTED {accepted_two} {answer_two}"
            await wait_for_log_entry(f"[{accepted_two}] SUCCESS")

        with open('/home/user/ci_states.log') as log:
            lines = [line.strip() for line in log if line.strip()]
        expected_log = [
            f"[{accepted_one}] INIT",
            f"[{accepted_one}] SUCCESS",
            f"[{accepted_two}] INIT",
            f"[{accepted_two}] SUCCESS",
        ]
        assert lines == expected_log, f"Unexpected state log: {lines!r}"
        assert not any(rejected in line for line in lines), "Rate-limited project was logged"

        with open('/home/user/config_merged.env') as merged:
            actual_two = [line.strip() for line in merged if line.strip()]
        assert actual_two == expected_two, f"Second dynamic merge mismatch: {actual_two!r} != {expected_two!r}"

    asyncio.run(run())
TEST_EOF

if timeout 45s python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
