#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import string
import subprocess
import pytest

def generate_random_hex(length):
    return ''.join(random.choice('0123456789abcdef') for _ in range(length))

def generate_random_string(length):
    return ''.join(random.choice(string.ascii_letters + string.digits) for _ in range(length))

def generate_inputs(n=1000, seed=42):
    random.seed(seed)
    lines = []
    trusted_hash = "88d4266fd4e6338d13b845fcf289579d209c897823b9217da3e161936f031589"

    for i in range(n):
        file_path = f"/var/www/app{random.randint(0, 999)}.php"

        if random.random() < 0.20:
            file_hash = trusted_hash
        else:
            file_hash = generate_random_hex(64)

        cwe_rand = random.random()
        if cwe_rand < 0.10:
            detected_cwe = "CWE-000"
        elif cwe_rand < 0.30:
            detected_cwe = "CWE-78"
        else:
            detected_cwe = random.choice(["CWE-400", "CWE-89", "CWE-22", "None"])

        audit_message = generate_random_string(random.randint(10, 30))

        line = f"{file_path}|{file_hash}|{detected_cwe}|{audit_message}"
        lines.append(line)

    return "\n".join(lines) + "\n"

def test_audit_parser_exists_and_executable():
    agent_script = "/home/user/audit_parser.sh"
    assert os.path.exists(agent_script), f"Agent script missing: {agent_script}"
    assert os.path.isfile(agent_script), f"Agent script is not a file: {agent_script}"
    assert os.access(agent_script, os.X_OK), f"Agent script is not executable: {agent_script}"

def test_fuzz_equivalence():
    oracle_script = "/tests/oracle.sh"
    agent_script = "/home/user/audit_parser.sh"

    assert os.path.exists(oracle_script), f"Oracle script missing: {oracle_script}"
    assert os.path.exists(agent_script), f"Agent script missing: {agent_script}"

    input_data = generate_inputs()

    oracle_proc = subprocess.run(
        ["bash", oracle_script],
        input=input_data.encode('utf-8'),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10
    )
    assert oracle_proc.returncode == 0, f"Oracle script failed with stderr: {oracle_proc.stderr.decode()}"
    oracle_output = oracle_proc.stdout.decode('utf-8')

    agent_proc = subprocess.run(
        ["bash", agent_script],
        input=input_data.encode('utf-8'),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10
    )
    assert agent_proc.returncode == 0, f"Agent script failed with stderr: {agent_proc.stderr.decode()}"
    agent_output = agent_proc.stdout.decode('utf-8')

    if oracle_output != agent_output:
        oracle_lines = oracle_output.splitlines()
        agent_lines = agent_output.splitlines()
        input_lines = input_data.splitlines()

        for i, (o_line, a_line) in enumerate(zip(oracle_lines, agent_lines)):
            if o_line != a_line:
                error_msg = (
                    f"Mismatch at line {i+1}:\n"
                    f"Input:  {input_lines[i]}\n"
                    f"Oracle: {o_line}\n"
                    f"Agent:  {a_line}\n"
                )
                pytest.fail(error_msg)

        assert len(oracle_lines) == len(agent_lines), "Output line counts differ."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
