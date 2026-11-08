#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import json
import os
import random
import re
import shutil
import string
import subprocess
import tempfile

import pytest


def generate_random_log_line():
    year = random.randint(2020, 2025)
    month = random.randint(1, 12)
    day = random.randint(1, 28)
    hour = random.randint(0, 23)
    minute = random.randint(0, 59)
    second = random.randint(0, 59)
    timestamp = f"{year}-{month:02d}-{day:02d}T{hour:02d}:{minute:02d}:{second:02d}Z"

    level = random.choice(["INFO", "WARN", "ERROR", "FATAL"])
    comp_len = random.randint(3, 10)
    component = "".join(random.choices(string.ascii_lowercase + string.digits + "-", k=comp_len))
    msg_len = random.randint(10, 50)
    message = "".join(random.choices(string.ascii_letters + string.digits + " ", k=msg_len))
    return f"[{timestamp}] {level} - {component}: {message}"


def expected_output(log_line):
    match = re.fullmatch(r"\[(.*?)\] (.*?) - (.*?): (.*)", log_line)
    assert match is not None
    timestamp, level, component, message = match.groups()
    if level == "FATAL":
        component = component.upper()
    return json.dumps(
        {
            "timestamp": timestamp,
            "level": level,
            "component": component,
            "message": message,
        },
        sort_keys=True,
        separators=(",", ":"),
    )


def run_parser(path, log_line):
    try:
        proc = subprocess.run(
            [path],
            input=log_line,
            text=True,
            capture_output=True,
            timeout=2,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Parser {path} timed out on input: {log_line}")
    assert proc.returncode == 0, f"Parser {path} failed on input: {log_line}\nError: {proc.stderr}"
    return proc.stdout.strip()


def test_restored_data_exists_and_expect_script_runs():
    restored = "/home/user/restored_data"
    oracle = os.path.join(restored, "oracle_parser")
    expect_script = "/home/user/restore.exp"

    assert os.path.isdir(restored), "Restored data directory is missing. Did the expect script run successfully?"
    assert os.path.isfile(oracle), "oracle_parser is missing from restored data."
    assert os.path.isfile(expect_script), "The required /home/user/restore.exp script is missing."
    assert not os.path.islink(expect_script), "restore.exp must be an Expect script, not a symlink."

    shutil.rmtree(restored)
    if os.path.exists("/app/oracle_parser"):
        os.remove("/app/oracle_parser")

    try:
        proc = subprocess.run(
            ["expect", expect_script],
            text=True,
            capture_output=True,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("restore.exp timed out while automating secure_restore.sh")

    assert proc.returncode == 0, f"restore.exp failed:\nstdout: {proc.stdout}\nstderr: {proc.stderr}"
    assert os.path.isdir(restored), "Running restore.exp did not recreate restored_data."
    assert os.path.isfile(oracle), "Running restore.exp did not restore oracle_parser."


def test_agent_binary_exists():
    path = "/home/user/uptime_parser"
    assert os.path.isfile(path), f"Agent's binary {path} is missing."
    assert os.access(path, os.X_OK), f"Agent's binary {path} is not executable."
    oracle = "/home/user/restored_data/oracle_parser"
    assert not filecmp.cmp(path, oracle, shallow=False), "uptime_parser is a byte-identical copy of oracle_parser."


@pytest.fixture(scope="session")
def rebuilt_bin():
    source = "/home/user/uptime_parser.go"
    assert os.path.isfile(source), "Required Go source /home/user/uptime_parser.go is missing."
    assert not os.path.islink(source), "uptime_parser.go must be an independently written source file, not a symlink."

    fd, output = tempfile.mkstemp(prefix="rebuilt_uptime_parser_")
    os.close(fd)
    os.unlink(output)
    env = os.environ.copy()
    env["GOFLAGS"] = ""
    env["GOWORK"] = "off"
    try:
        proc = subprocess.run(
            ["go", "build", "-trimpath", "-o", output, source],
            text=True,
            capture_output=True,
            timeout=60,
            env=env,
        )
        assert proc.returncode == 0, f"uptime_parser.go does not build successfully:\n{proc.stderr}"
        assert os.path.isfile(output) and os.access(output, os.X_OK), "Go build did not produce an executable."
        oracle = "/home/user/restored_data/oracle_parser"
        assert not filecmp.cmp(output, oracle, shallow=False), "The rebuilt program is byte-identical to oracle_parser."
        yield output
    finally:
        if os.path.exists(output):
            os.remove(output)


def test_go_source_builds(rebuilt_bin):
    assert os.path.isfile(rebuilt_bin)


def test_fuzz_equivalence(rebuilt_bin):
    agent_bin = "/home/user/uptime_parser"
    oracle_bin = "/home/user/restored_data/oracle_parser"
    if not os.path.isfile(oracle_bin):
        oracle_bin = "/app/oracle_parser"

    assert os.path.isfile(oracle_bin), "Oracle binary not found."
    assert os.path.isfile(agent_bin), "Agent binary not found."

    random.seed(42)
    for _ in range(100):
        log_line = generate_random_log_line()
        expected = expected_output(log_line)

        oracle_out = run_parser(oracle_bin, log_line)
        agent_out = run_parser(agent_bin, log_line)
        rebuilt_out = run_parser(rebuilt_bin, log_line)

        assert oracle_out == expected, f"Oracle disagreed with derived result on input: {log_line}"
        assert agent_out == oracle_out, (
            f"Mismatch on input: {log_line}\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent): {agent_out}"
        )
        assert rebuilt_out == expected, (
            f"Rebuilt Go source mismatch on input: {log_line}\n"
            f"Expected: {expected}\n"
            f"Got: {rebuilt_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
