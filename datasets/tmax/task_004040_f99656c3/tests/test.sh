#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import pytest


def generate_random_path(length):
    components = []
    for _ in range(length):
        choice = random.random()
        if choice < 0.2:
            components.append("..")
        elif choice < 0.3:
            components.append(".")
        elif choice < 0.4:
            components.append("")
        else:
            name_len = random.randint(1, 10)
            name = "".join(random.choices(string.ascii_letters + string.digits + "_", k=name_len))
            components.append(name)

    path = "/".join(components)
    if random.random() < 0.2:
        path = "/" + path
    if random.random() < 0.2:
        path = path + "/"
    return path


def run_program(executable, input_data, description):
    try:
        process = subprocess.run(
            [executable],
            input=input_data,
            text=True,
            capture_output=True,
            timeout=10
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{description} timed out on fuzz inputs.")

    assert process.returncode == 0, \
        f"{description} exited with status {process.returncode}: {process.stderr}"
    return process.stdout.splitlines()


def test_fuzz_equivalence():
    agent_source = "/home/user/path_resolver.cpp"
    agent_executable = "/home/user/path_resolver"
    oracle_executable = "/tests/oracle_path_resolver"
    rebuilt_executable = "/tmp/path_resolver_from_source"

    assert os.path.isfile(agent_source), f"Agent source not found at {agent_source}"
    assert os.path.getsize(agent_source) > 0, f"Agent source {agent_source} is empty"

    assert os.path.isfile(agent_executable), f"Agent executable not found at {agent_executable}"
    assert os.access(agent_executable, os.X_OK), f"Agent executable {agent_executable} is not executable"

    assert os.path.isfile(oracle_executable), f"Oracle executable not found at {oracle_executable}"
    assert os.access(oracle_executable, os.X_OK), f"Oracle executable {oracle_executable} is not executable"

    try:
        compile_process = subprocess.run(
            ["g++", "-O2", agent_source, "-o", rebuilt_executable],
            text=True,
            capture_output=True,
            timeout=20
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Compiling the submitted C++ source timed out.")

    assert compile_process.returncode == 0, \
        f"Submitted C++ source failed to compile:\n{compile_process.stderr}"

    random.seed(42)
    num_tests = 10000

    inputs = []
    for _ in range(num_tests):
        length = random.randint(1, 50)
        inputs.append(generate_random_path(length))

    input_data = "\n".join(inputs) + "\n"

    agent_outputs = run_program(agent_executable, input_data, "Agent executable")
    rebuilt_outputs = run_program(rebuilt_executable, input_data, "Executable rebuilt from submitted source")
    oracle_outputs = run_program(oracle_executable, input_data, "Oracle executable")

    assert len(agent_outputs) == len(oracle_outputs), \
        f"Output line count mismatch: expected {len(oracle_outputs)}, got {len(agent_outputs)}"
    assert len(rebuilt_outputs) == len(oracle_outputs), \
        f"Rebuilt source output line count mismatch: expected {len(oracle_outputs)}, got {len(rebuilt_outputs)}"

    for i, (agent_out, rebuilt_out, oracle_out) in enumerate(zip(agent_outputs, rebuilt_outputs, oracle_outputs)):
        assert agent_out == oracle_out, \
            f"Mismatch on input '{inputs[i]}':\nExpected: {oracle_out}\nGot: {agent_out}"
        assert rebuilt_out == oracle_out, \
            f"Submitted source mismatch on input '{inputs[i]}':\nExpected: {oracle_out}\nGot: {rebuilt_out}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
