#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import urllib.parse
import pytest

def test_files_exist():
    assert os.path.isfile('/home/user/auth_checker.cpp'), "Missing /home/user/auth_checker.cpp"
    assert os.path.isfile('/home/user/Makefile'), "Missing /home/user/Makefile"

def test_makefile_proxy_target():
    with open('/home/user/Makefile', 'r') as f:
        content = f.read()
    assert 'proxy:' in content, "Makefile is missing the 'proxy:' target"

def test_binary_exists_and_executable():
    # Always rebuild so the checked binary is produced by the submitted project.
    binary = '/home/user/auth_checker'
    if os.path.lexists(binary):
        os.remove(binary)

    proc = subprocess.run(['make'], cwd='/home/user', capture_output=True, text=True)
    assert proc.returncode == 0, f"make failed:\n{proc.stdout}\n{proc.stderr}"
    assert os.path.isfile(binary), "Binary /home/user/auth_checker was not built"
    assert os.access(binary, os.X_OK), "Binary /home/user/auth_checker is not executable"

def generate_fuzz_inputs(n=1000):
    random.seed(42)
    services = ['GATEWAY', 'AUTH', 'USER_DB', 'PAYMENT', 'LEDGER', 'FRAUD']
    inputs = []
    for _ in range(n):
        parts = []
        num_parts = random.randint(1, 15)
        for _ in range(num_parts):
            if random.random() < 0.7:
                parts.append(random.choice(services))
            else:
                noise = ''.join(random.choices('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-%', k=random.randint(2, 10)))
                parts.append(noise)
        raw_str = ','.join(parts)
        encoded = urllib.parse.quote(raw_str)
        # Ensure length constraint (roughly)
        if len(encoded) > 150:
            encoded = encoded[:150]
        inputs.append(encoded)
    return inputs

def expected_output(encoded):
    decoded = urllib.parse.unquote_plus(encoded)

    # Match comma-delimited getline behavior, including omission of a final
    # empty field when the decoded string ends in a comma.
    if decoded == '':
        nodes = []
    else:
        nodes = decoded.split(',')
        if decoded.endswith(','):
            nodes.pop()

    if not nodes:
        return 'ALLOW'

    all_nodes = {'GATEWAY', 'AUTH', 'USER_DB', 'PAYMENT', 'LEDGER', 'FRAUD'}
    graph = {
        'GATEWAY': {'AUTH', 'PAYMENT'},
        'AUTH': {'USER_DB'},
        'PAYMENT': {'LEDGER', 'FRAUD'},
    }

    if nodes[0] not in all_nodes:
        return 'DENY:' + nodes[0]

    for current, following in zip(nodes, nodes[1:]):
        if following not in graph.get(current, set()):
            return 'DENY:' + following

    return 'ALLOW'

def test_fuzz_equivalence():
    agent_path = '/home/user/auth_checker'
    assert os.path.isfile(agent_path), "Agent binary missing"

    inputs = generate_fuzz_inputs(1000)

    for fuzzed_input in inputs:
        agent_proc = subprocess.run([agent_path, fuzzed_input], capture_output=True, text=True)
        expected = expected_output(fuzzed_input)
        agent_out = agent_proc.stdout.strip()

        assert agent_out == expected, (
            f"Mismatch on input: {fuzzed_input}\n"
            f"Expected output: {expected}\n"
            f"Agent output: {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
