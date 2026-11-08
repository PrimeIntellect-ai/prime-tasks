#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import string
import pytest

ORACLE_PATH = "/tests/oracle_config_manager"
AGENT_PATH = "/home/user/config_manager"
SOURCE_PATH = "/home/user/solution.cpp"
SHIFT_KEY = "14"
NUM_ITERATIONS = 200

def generate_random_string(min_len=3, max_len=10):
    length = random.randint(min_len, max_len)
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

def generate_commands(iteration):
    num_commands = random.randint(10, 50)
    commands = []
    files_used = set()
    keys_used = []

    for _ in range(num_commands):
        cmd_type = random.choice(["SET", "DEL", "COMMIT", "LOAD", "DUMP"])
        if cmd_type == "SET":
            key = generate_random_string()
            val = generate_random_string()
            commands.append(f"SET {key} {val}")
            keys_used.append(key)
        elif cmd_type == "DEL":
            key = random.choice(keys_used) if keys_used else generate_random_string()
            commands.append(f"DEL {key}")
        elif cmd_type == "COMMIT":
            filepath = f"/tmp/fuzz_file_{iteration}_{random.randint(1, 5)}.txt"
            commands.append(f"COMMIT {filepath}")
            files_used.add(filepath)
        elif cmd_type == "LOAD":
            if files_used:
                filepath = random.choice(list(files_used))
                commands.append(f"LOAD {filepath}")
            else:
                filepath = f"/tmp/fuzz_file_{iteration}_{random.randint(1, 5)}.txt"
                commands.append(f"LOAD {filepath}")
                files_used.add(filepath)
        elif cmd_type == "DUMP":
            commands.append("DUMP")

    return "\n".join(commands) + "\n", list(files_used)

def run_program(executable, commands, files_used):
    # Ensure files don't exist before running
    for f in files_used:
        if os.path.exists(f):
            os.remove(f)

    process = subprocess.Popen(
        [executable, SHIFT_KEY],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=False
    )

    stdout, stderr = process.communicate(input=commands.encode('utf-8'))

    file_states = {}
    for f in files_used:
        if os.path.exists(f):
            with open(f, 'rb') as file_obj:
                file_states[f] = file_obj.read()
            os.remove(f)
        else:
            file_states[f] = None

    return stdout, file_states

def test_agent_compilation():
    assert os.path.exists(SOURCE_PATH), f"Agent source not found at {SOURCE_PATH}"
    assert os.path.isfile(SOURCE_PATH), f"Agent source path {SOURCE_PATH} is not a file"
    assert os.path.exists(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Agent path {AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary {AGENT_PATH} is not executable"

def test_fuzz_equivalence():
    random.seed(42)

    for i in range(NUM_ITERATIONS):
        commands, files_used = generate_commands(i)

        oracle_stdout, oracle_files = run_program(ORACLE_PATH, commands, files_used)
        agent_stdout, agent_files = run_program(AGENT_PATH, commands, files_used)

        assert agent_stdout == oracle_stdout, (
            f"Iteration {i}: stdout mismatch.\n"
            f"Commands:\n{commands}\n"
            f"Oracle stdout:\n{oracle_stdout}\n"
            f"Agent stdout:\n{agent_stdout}"
        )

        for f in files_used:
            assert agent_files[f] == oracle_files[f], (
                f"Iteration {i}: file content mismatch for {f}.\n"
                f"Commands:\n{commands}\n"
                f"Oracle file content: {oracle_files[f]}\n"
                f"Agent file content: {agent_files[f]}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
