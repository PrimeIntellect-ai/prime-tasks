#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import random
import secrets
import stat
import subprocess

import pytest

ORACLE_PATH = "/app/oracle_bin"
AGENT_PATH = "/home/user/evaluator.py"
N_TESTS = 1000


def run_cmd(cmd, arg=None):
    full_cmd = list(cmd)
    if arg is not None:
        full_cmd.append(arg)
    try:
        result = subprocess.run(
            full_cmd,
            capture_output=True,
            text=True,
            timeout=2,
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "Timeout"


def run_agent(arg=None):
    return run_cmd(
        ["runuser", "-u", "user", "--", "python3", AGENT_PATH], arg
    )


@pytest.fixture(scope="session", autouse=True)
def protect_task_files():
    app_mode = stat.S_IMODE(os.stat("/app").st_mode)
    oracle_mode = stat.S_IMODE(os.stat(ORACLE_PATH).st_mode)
    os.chmod("/app", 0o555)
    os.chmod(ORACLE_PATH, 0o555)
    try:
        yield
    finally:
        if os.path.exists(ORACLE_PATH):
            os.chmod(ORACLE_PATH, oracle_mode)
        os.chmod("/app", app_mode)


def generate_fuzz_inputs(n, seed=42):
    random.seed(seed)
    inputs = []
    for _ in range(n):
        choice = random.random()
        if choice < 0.2:
            length = random.randint(10, 100)
            data = bytes(random.getrandbits(8) for _ in range(length))
        elif choice < 0.4:
            header = b"WRONG_HD"
            opcode = random.choice([0x10, 0x20, 0x30])
            payload = b" ".join(
                str(random.randint(-100, 100)).encode()
                for _ in range(random.randint(1, 10))
            )
            data = header + bytes([opcode]) + len(payload).to_bytes(2, "big") + payload
        elif choice < 0.6:
            header = b"CALC_V2!"
            opcode = random.choice([0x00, 0x40, 0xFF])
            payload = b" ".join(
                str(random.randint(-100, 100)).encode()
                for _ in range(random.randint(1, 10))
            )
            data = header + bytes([opcode]) + len(payload).to_bytes(2, "big") + payload
        elif choice < 0.8:
            header = b"CALC_V2!"
            opcode = random.choice([0x10, 0x20, 0x30])
            payload = b"12 34 abc 56"
            data = header + bytes([opcode]) + len(payload).to_bytes(2, "big") + payload
        else:
            header = b"CALC_V2!"
            opcode = random.choice([0x10, 0x20, 0x30])
            payload = b" ".join(
                str(random.randint(-100, 100)).encode()
                for _ in range(random.randint(1, 10))
            )
            data = header + bytes([opcode]) + len(payload).to_bytes(2, "big") + payload
        inputs.append(base64.b64encode(data).decode("ascii"))
    return inputs


def expected_result(arg):
    try:
        data = base64.b64decode(arg)
    except Exception:
        return 1, "ERROR: INVALID_HEADER\n", ""

    if not data.startswith(b"CALC_V2!"):
        return 1, "ERROR: INVALID_HEADER\n", ""
    if len(data) < 11:
        return 1, "ERROR: UNKNOWN_OPCODE\n", ""

    opcode = data[8]
    if opcode not in (0x10, 0x20, 0x30):
        return 1, "ERROR: UNKNOWN_OPCODE\n", ""

    length = (data[9] << 8) | data[10]
    payload = data[11:11 + length].decode("ascii", errors="ignore")
    try:
        ints = [int(x) for x in payload.split()]
    except Exception:
        ints = []

    if not ints:
        return 0, "0\n", ""

    result = ints[0]
    for value in ints[1:]:
        if opcode == 0x10:
            result += value
        elif opcode == 0x20:
            result -= value
        else:
            result *= value
    return 0, f"{result}\n", ""


def independent_inputs(n=300):
    rng = secrets.SystemRandom()
    values = ["", "!!!!", "A", "====", "Q0FMQ19WMg=="]
    for _ in range(n):
        kind = rng.randrange(7)
        if kind == 0:
            data = os.urandom(rng.randint(0, 80))
        elif kind == 1:
            data = b"CALC_V2!" + os.urandom(rng.randint(0, 2))
        else:
            header = b"CALC_V2!" if kind != 2 else os.urandom(8)
            opcode = rng.choice([0x10, 0x20, 0x30, 0x00, 0x40, 0xFF])
            if kind == 3:
                payload = b"12 34 bad 56"
            elif kind == 4:
                payload = os.urandom(rng.randint(0, 40))
            else:
                payload = b" ".join(
                    str(rng.randint(-10000, 10000)).encode()
                    for _ in range(rng.randint(0, 20))
                )
            declared = rng.choice([len(payload), 0, rng.randint(0, 100)])
            data = header + bytes([opcode]) + declared.to_bytes(2, "big") + payload
            if kind == 6:
                data += os.urandom(rng.randint(1, 20))
        values.append(base64.b64encode(data).decode("ascii"))
    return values


def test_agent_artifact():
    assert os.path.isfile(AGENT_PATH), f"Agent script not found at {AGENT_PATH}"
    assert not os.path.islink(AGENT_PATH), "Agent script must be a regular file, not a symlink"
    assert os.access(AGENT_PATH, os.X_OK), "Agent script is not executable"
    with open(AGENT_PATH, "rb") as handle:
        assert handle.readline().rstrip(b"\r\n") == b"#!/usr/bin/env python3"


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    assert os.path.exists(AGENT_PATH), f"Agent script not found at {AGENT_PATH}"

    for i, b64_input in enumerate(generate_fuzz_inputs(N_TESTS)):
        oracle_code, oracle_out, oracle_err = run_cmd([ORACLE_PATH], b64_input)
        agent_code, agent_out, agent_err = run_agent(b64_input)
        error_msg = (
            f"Mismatch on input {i}:\n"
            f"Input (base64): {b64_input}\n"
            f"Oracle return code: {oracle_code}, Agent return code: {agent_code}\n"
            f"Oracle stdout: {oracle_out!r}, Agent stdout: {agent_out!r}\n"
            f"Oracle stderr: {oracle_err!r}, Agent stderr: {agent_err!r}"
        )
        assert oracle_code == agent_code, error_msg
        assert oracle_out == agent_out, error_msg
        assert oracle_err == agent_err, error_msg


def test_independent_behavior_without_oracle():
    hidden_oracle = f"/root/oracle_bin.hidden.{os.getpid()}"
    original_mode = stat.S_IMODE(os.stat(ORACLE_PATH).st_mode)
    os.replace(ORACLE_PATH, hidden_oracle)
    os.chmod(hidden_oracle, 0o700)
    try:
        assert run_agent() == (0, "", "")
        for i, arg in enumerate(independent_inputs()):
            expected = expected_result(arg)
            actual = run_agent(arg)
            assert actual == expected, (
                f"Independent mismatch on input {i}: {arg}\n"
                f"Expected: {expected!r}\nActual: {actual!r}"
            )
    finally:
        os.chmod(hidden_oracle, original_mode)
        os.replace(hidden_oracle, ORACLE_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
