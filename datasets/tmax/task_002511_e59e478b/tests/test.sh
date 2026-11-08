#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import random
import string
import tempfile
import pytest

AGENT_SCRIPT = "/home/user/sign_request.py"
ORACLE_BINARY = "/app/legacy_signer"


def generate_inputs(n=1000):
    random.seed(42)
    inputs = []

    # 70% valid alphanumeric strings of length 8 to 32
    for _ in range(int(n * 0.7)):
        length = random.randint(8, 32)
        inputs.append("".join(random.choices(string.ascii_letters + string.digits, k=length)))

    # 10% strings shorter than 8 characters
    for _ in range(int(n * 0.1)):
        length = random.randint(1, 7)
        inputs.append("".join(random.choices(string.ascii_letters + string.digits, k=length)))

    # 10% strings longer than 32 characters
    for _ in range(int(n * 0.1)):
        length = random.randint(33, 64)
        inputs.append("".join(random.choices(string.ascii_letters + string.digits, k=length)))

    # 10% strings containing non-alphanumeric characters
    for _ in range(int(n * 0.1)):
        length = random.randint(8, 32)
        s = list("".join(random.choices(string.ascii_letters + string.digits, k=length)))
        s[random.randint(0, length - 1)] = random.choice("!@#$%^&*()_+~`-=[]{}|;':,./<>?")
        inputs.append("".join(s))

    random.shuffle(inputs)
    return inputs


def run_cmd(cmd):
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=2)
        return result.stdout, result.stderr, result.returncode
    except subprocess.TimeoutExpired:
        return "", "Timeout", -1


def run_agent(args):
    fd, trace_path = tempfile.mkstemp(prefix="agent_trace_", dir="/tmp")
    os.close(fd)
    try:
        cmd = [
            "strace", "-f", "-qq", "-e", "trace=process",
            "-o", trace_path, "--", "python3", AGENT_SCRIPT, *args
        ]
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=2)
            stdout, stderr, code = result.stdout, result.stderr, result.returncode
        except subprocess.TimeoutExpired:
            return "", "Timeout", -1, True

        with open(trace_path, "r", errors="replace") as f:
            trace = f.read()

        # The first successful execve is the Python interpreter. Any additional
        # successful exec proves that the submitted implementation delegated its
        # work to another executable rather than implementing the signer in Python.
        successful_execs = re.findall(r'execve\(.*?\)\s+=\s+0(?:\s|$)', trace)
        delegated = len(successful_execs) > 1
        return stdout, stderr, code, delegated
    finally:
        try:
            os.unlink(trace_path)
        except FileNotFoundError:
            pass


def test_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"
    assert os.path.exists(ORACLE_BINARY), "Oracle binary missing"
    with open(AGENT_SCRIPT, "rb") as agent_file, open(ORACLE_BINARY, "rb") as oracle_file:
        assert agent_file.read() != oracle_file.read(), "Submission is byte-identical to the oracle"


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_BINARY), "Oracle binary missing"

    inputs = generate_inputs(1000)
    argument_lists = [[], ["arg1", "arg2"]] + [[inp] for inp in inputs]

    # Derive all expected results while the oracle is available, then remove it
    # before executing any submitted code so /app/legacy_signer cannot be used as
    # a runtime dependency.
    expected = []
    for args in argument_lists:
        expected.append(run_cmd([ORACLE_BINARY, *args]))
    os.unlink(ORACLE_BINARY)

    for args, (o_out, o_err, o_code) in zip(argument_lists, expected):
        a_out, a_err, a_code, delegated = run_agent(args)
        assert not delegated, f"Submitted script delegated to another executable for args {args!r}"
        assert o_out == a_out, f"Mismatch on stdout for args {args!r}. Expected: {o_out!r}, Got: {a_out!r}"
        assert o_code == a_code, f"Mismatch on return code for args {args!r}. Expected: {o_code}, Got: {a_code}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
