#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import string
import subprocess
import tempfile
import base64
import binascii
import sys

def generate_fuzz_file(filepath):
    with open(filepath, 'w') as f:
        num_lines = random.randint(10, 100)
        for _ in range(num_lines):
            choice = random.random()
            if choice < 0.33:
                # Valid base64 encoded hex string
                text = ''.join(random.choices(string.ascii_letters + string.digits + " ", k=random.randint(5, 20)))
                hex_str = binascii.hexlify(text.encode('ascii')).decode('ascii')
                b64 = base64.b64encode(hex_str.encode('ascii')).decode('ascii')
                f.write(b64 + '\n')
            elif choice < 0.66:
                # Corrupted Base64
                text = ''.join(random.choices(string.ascii_letters + string.digits + " ", k=random.randint(5, 20)))
                hex_str = binascii.hexlify(text.encode('ascii')).decode('ascii')
                b64 = base64.b64encode(hex_str.encode('ascii')).decode('ascii')
                # Interleave with spaces, punctuation
                b64_list = list(b64)
                for _ in range(random.randint(1, 5)):
                    b64_list.insert(random.randint(0, len(b64_list)), random.choice(" !@#$%^&*()"))
                # Maybe remove padding
                b64 = ''.join(b64_list).rstrip('=')
                f.write(b64 + '\n')
            else:
                # Hopelessly corrupted
                f.write(''.join(random.choices(string.printable, k=random.randint(10, 50))) + '\n')

def test_fuzz_equivalence():
    agent_script = "/home/user/parser.sh"
    oracle_bin = "/tests/oracle_parser"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} not found."
    assert os.path.isfile(oracle_bin), f"Oracle binary {oracle_bin} not found."

    random.seed(42)
    N = 100 # Reduced from 1000 to avoid test timeouts while still providing robust coverage

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(N):
            input_file = os.path.join(tmpdir, f"input_{i}.txt")
            generate_fuzz_file(input_file)

            # Run oracle
            oracle_proc = subprocess.run([sys.executable, oracle_bin, input_file], capture_output=True, text=True)
            oracle_out = oracle_proc.stdout

            # Run agent
            agent_proc = subprocess.run(["bash", agent_script, input_file], capture_output=True, text=True)
            agent_out = agent_proc.stdout

            if oracle_out != agent_out:
                with open(input_file, 'r') as f:
                    input_content = f.read()
                error_msg = (
                    f"Mismatch on file {i}:\n\n"
                    f"--- INPUT ---\n{input_content}\n"
                    f"--- EXPECTED (Oracle) ---\n{oracle_out}\n"
                    f"--- ACTUAL (Agent) ---\n{agent_out}\n"
                )
                assert False, error_msg
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
