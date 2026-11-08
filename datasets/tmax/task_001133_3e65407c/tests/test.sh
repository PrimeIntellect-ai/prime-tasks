#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
from collections import deque
from fractions import Fraction

import pytest

AGENT = "/home/user/linreg.py"
CI_SCRIPT = "/home/user/ci_test.sh"
ORACLE = "/app/linreg_ref"


def exact_output(commands):
    points = deque()
    n = 0
    sum_x = 0
    sum_y = 0
    sum_xx = 0
    sum_xy = 0
    output = []

    for command in commands:
        parts = command.split()
        if parts[0] == "ADD":
            x, y = int(parts[1]), int(parts[2])
            points.append((x, y))
            n += 1
            sum_x += x
            sum_y += y
            sum_xx += x * x
            sum_xy += x * y
        elif parts[0] == "REMOVE_OLDEST":
            if not points:
                output.append("ERROR")
            else:
                x, y = points.popleft()
                n -= 1
                sum_x -= x
                sum_y -= y
                sum_xx -= x * x
                sum_xy -= x * y
        elif parts[0] == "PREDICT":
            x = int(parts[1])
            if n < 2:
                output.append("ERROR")
                continue
            denominator_component = n * sum_xx - sum_x * sum_x
            if denominator_component == 0:
                output.append("ERROR")
                continue
            slope_numerator = n * sum_xy - sum_x * sum_y
            numerator = sum_y * denominator_component + slope_numerator * (n * x - sum_x)
            value = Fraction(numerator, n * denominator_component)
            if value.denominator == 1:
                output.append(str(value.numerator))
            else:
                output.append(f"{value.numerator}/{value.denominator}")
        else:
            raise AssertionError(f"Invalid test command: {command}")

    return "".join(line + "\n" for line in output)


def run_agent(commands, timeout=20):
    input_data = "\n".join(commands) + "\n"
    proc = subprocess.run(
        ["python3", AGENT],
        input=input_data,
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    assert proc.returncode == 0, f"linreg.py exited with {proc.returncode}: {proc.stderr}"
    assert proc.stderr == "", f"linreg.py wrote unexpected stderr: {proc.stderr}"
    return proc.stdout


def validate_ci_input(data):
    lines = data.splitlines()
    assert len(lines) == 1000, f"CI generated {len(lines)} commands instead of 1000"
    pattern = re.compile(r"(?:ADD [+-]?\d+ [+-]?\d+|REMOVE_OLDEST|PREDICT [+-]?\d+)")
    for index, line in enumerate(lines):
        assert pattern.fullmatch(line), f"Invalid generated command at line {index + 1}: {line!r}"


def test_ci_test_sh_exists_and_behaves_as_required():
    path = CI_SCRIPT
    assert os.path.exists(path), f"CI script {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."
    assert os.access(path, os.X_OK) or "bash" in open(path).read(), f"{path} should be an executable bash script."

    syntax = subprocess.run(["bash", "-n", path], text=True, capture_output=True)
    assert syntax.returncode == 0, f"CI script has invalid bash syntax: {syntax.stderr}"

    oracle_backup = "/tmp/linreg_ref.verifier_backup"
    agent_backup = "/tmp/linreg.py.verifier_backup"
    mode_path = "/tmp/linreg_ci_probe_mode"
    oracle_log = "/tmp/linreg_ci_oracle_input"
    agent_log = "/tmp/linreg_ci_agent_input"

    for temporary in (oracle_backup, agent_backup, mode_path, oracle_log, agent_log):
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass

    os.replace(ORACLE, oracle_backup)
    os.replace(AGENT, agent_backup)
    try:
        oracle_probe = '''#!/usr/bin/env python3
import os
import sys
data = sys.stdin.read()
with open("/tmp/linreg_ci_oracle_input", "w") as f:
    f.write(data)
mode = open("/tmp/linreg_ci_probe_mode").read().strip()
print("SAME" if mode == "same" else "ORACLE_ONLY")
'''
        agent_probe = '''import sys
data = sys.stdin.read()
with open("/tmp/linreg_ci_agent_input", "w") as f:
    f.write(data)
mode = open("/tmp/linreg_ci_probe_mode").read().strip()
print("SAME" if mode == "same" else "AGENT_ONLY")
'''
        with open(ORACLE, "w") as f:
            f.write(oracle_probe)
        os.chmod(ORACLE, 0o755)
        with open(AGENT, "w") as f:
            f.write(agent_probe)
        os.chmod(AGENT, 0o644)

        with open(mode_path, "w") as f:
            f.write("same")
        success = subprocess.run(
            ["bash", path], text=True, capture_output=True, timeout=30, cwd="/tmp"
        )
        assert success.returncode == 0, (
            "CI script must exit 0 when oracle and Python outputs match.\n"
            f"stdout:\n{success.stdout}\nstderr:\n{success.stderr}"
        )
        assert os.path.exists(oracle_log), "CI script did not run /app/linreg_ref"
        assert os.path.exists(agent_log), "CI script did not run python3 /home/user/linreg.py"
        with open(oracle_log) as f:
            oracle_input = f.read()
        with open(agent_log) as f:
            agent_input = f.read()
        assert oracle_input == agent_input, "CI script did not feed the same test file to both programs"
        validate_ci_input(oracle_input)

        os.unlink(oracle_log)
        os.unlink(agent_log)
        with open(mode_path, "w") as f:
            f.write("mismatch")
        mismatch = subprocess.run(
            ["bash", path], text=True, capture_output=True, timeout=30, cwd="/tmp"
        )
        assert mismatch.returncode != 0, "CI script must exit nonzero when outputs differ"
        combined = mismatch.stdout + mismatch.stderr
        assert "ORACLE_ONLY" in combined and "AGENT_ONLY" in combined, (
            "CI script must print the diff when outputs differ"
        )
        assert os.path.exists(oracle_log), "CI script did not run the oracle in mismatch case"
        assert os.path.exists(agent_log), "CI script did not run the Python program in mismatch case"
        with open(oracle_log) as f:
            oracle_input = f.read()
        with open(agent_log) as f:
            agent_input = f.read()
        assert oracle_input == agent_input, "CI mismatch run used different inputs for the two programs"
        validate_ci_input(oracle_input)
    finally:
        for probe in (ORACLE, AGENT):
            try:
                os.unlink(probe)
            except FileNotFoundError:
                pass
        os.replace(oracle_backup, ORACLE)
        os.replace(agent_backup, AGENT)
        for temporary in (mode_path, oracle_log, agent_log):
            try:
                os.unlink(temporary)
            except FileNotFoundError:
                pass


def test_linreg_fuzz_exact_arithmetic():
    assert os.path.exists(ORACLE), f"Oracle {ORACLE} missing."
    assert os.path.exists(AGENT), f"Agent script {AGENT} missing."
    assert os.path.isfile(AGENT), f"Agent script {AGENT} is not a file."
    with open(ORACLE, "rb") as oracle_file, open(AGENT, "rb") as agent_file:
        assert oracle_file.read() != agent_file.read(), "Submission must not be a byte-identical copy of the reference"

    random.seed(42)
    for iteration in range(100):
        num_commands = random.randint(1000, 5000)
        commands = []
        for _ in range(num_commands):
            r = random.random()
            if r < 0.5:
                x = random.randint(-10000, 10000)
                y = random.randint(-10000, 10000)
                commands.append(f"ADD {x} {y}")
            elif r < 0.75:
                commands.append("REMOVE_OLDEST")
            else:
                x = random.randint(-10000, 10000)
                commands.append(f"PREDICT {x}")

        expected = exact_output(commands)
        actual = run_agent(commands)
        assert actual == expected, f"Exact-arithmetic mismatch on fuzz iteration {iteration}"


def test_values_beyond_signed_64_bit_intermediates():
    commands = [f"ADD {x} 10000" for x in range(1, 5001)]
    commands.extend(["PREDICT 10000", "PREDICT -10000"])
    expected = exact_output(commands)
    assert expected == "10000\n10000\n"
    assert run_agent(commands) == expected


def test_constant_time_updates_and_predictions():
    count = 120000
    commands = [f"ADD {i % 1000} {3 * (i % 1000) + 1}" for i in range(count)]
    commands.extend(["PREDICT 17"] * 2500)
    commands.extend(["REMOVE_OLDEST"] * count)
    commands.append("REMOVE_OLDEST")
    expected = ("52\n" * 2500) + "ERROR\n"
    actual = run_agent(commands, timeout=8)
    assert actual == expected
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
