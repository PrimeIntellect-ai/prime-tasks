#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import re
import string
import subprocess
import pytest

def test_str_tool_built():
    tool_path = "/app/string_utils-1.2.0/str_tool"
    package_path = "/app/string_utils-1.2.0"
    makefile_path = os.path.join(package_path, "Makefile")

    assert os.path.isfile(tool_path), f"{tool_path} executable not found. Did you run make?"
    assert os.access(tool_path, os.X_OK), f"{tool_path} is not executable."
    assert os.path.isfile(makefile_path), f"{makefile_path} not found."

    with open(makefile_path, encoding="utf-8") as makefile:
        active_makefile = "\n".join(line.split("#", 1)[0] for line in makefile)
    assert re.search(r"(?<![A-Za-z0-9_])gcc(?![A-Za-z0-9_])", active_makefile), \
        "Makefile does not use gcc."
    assert "-lm" in active_makefile, "Makefile does not link the math library with -lm."

    build = subprocess.run(
        ["make", "-B", "str_tool"],
        cwd=package_path,
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, \
        f"Makefile rebuild failed.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    assert os.path.isfile(tool_path), f"{tool_path} was not produced by make."
    assert os.access(tool_path, os.X_OK), f"{tool_path} produced by make is not executable."

    encoded = subprocess.run(
        [tool_path, "encode", "a b,/"], capture_output=True, text=True
    )
    assert encoded.returncode == 0, "str_tool encode failed."
    assert encoded.stdout == "a%20b%2C%2F", "str_tool URL encoding is incorrect."

def test_interpreter_exists_and_executable():
    script_path = "/home/user/api_interpreter.sh"
    assert os.path.isfile(script_path), f"{script_path} not found."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

def generate_random_var():
    return ''.join(random.choices(string.ascii_lowercase, k=random.randint(1, 5)))

def generate_random_val():
    return ''.join(random.choices(string.ascii_letters + string.digits, k=random.randint(1, 10)))

def generate_fuzz_input():
    num_commands = random.randint(1, 10)
    commands = []
    variables = [generate_random_var() for _ in range(4)]

    for _ in range(num_commands - 1):
        cmd_type = random.choice(['SET', 'APPEND', 'SORT', 'MERGE', 'URLENCODE'])
        var1 = random.choice(variables)
        if cmd_type == 'SET':
            commands.append(f"SET {var1} {generate_random_val()}")
        elif cmd_type == 'APPEND':
            commands.append(f"APPEND {var1} {generate_random_val()}")
        elif cmd_type == 'SORT':
            commands.append(f"SORT {var1}")
        elif cmd_type == 'MERGE':
            var2 = random.choice(variables)
            commands.append(f"MERGE {var1} {var2}")
        elif cmd_type == 'URLENCODE':
            commands.append(f"URLENCODE {var1}")

    commands.append("JSON")
    return " | ".join(commands)

def test_fuzz_equivalence():
    oracle_path = "/tests/reference_oracle.sh"
    agent_path = "/home/user/api_interpreter.sh"

    assert os.path.isfile(oracle_path), "Reference oracle missing"
    assert os.path.isfile(agent_path), "Agent script missing"

    random.seed(42)

    for i in range(1000):
        dsl_input = generate_fuzz_input()

        oracle_proc = subprocess.run(["bash", oracle_path, dsl_input], capture_output=True, text=True)
        agent_proc = subprocess.run([agent_path, dsl_input], capture_output=True, text=True)

        assert oracle_proc.returncode == agent_proc.returncode, \
            f"Return code mismatch on input: {dsl_input}\nOracle: {oracle_proc.returncode}\nAgent: {agent_proc.returncode}"

        assert oracle_proc.stdout == agent_proc.stdout, \
            f"Output mismatch on input: {dsl_input}\nOracle stdout:\n{oracle_proc.stdout}\nAgent stdout:\n{agent_proc.stdout}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
