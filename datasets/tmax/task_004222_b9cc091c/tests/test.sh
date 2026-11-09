#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

def test_obfuscator_script_exists_and_executable():
    script_path = "/home/user/obfuscator.py"
    assert os.path.isfile(script_path), f"Missing script file: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"

def test_symlink_exists_and_correct():
    symlink_path = "/home/user/bin/obfuscate_stream"
    script_path = "/home/user/obfuscator.py"
    assert os.path.islink(symlink_path), f"Not a symbolic link: {symlink_path}"
    target = os.readlink(symlink_path)
    # allow absolute or relative symlink
    if not os.path.isabs(target):
        target = os.path.normpath(os.path.join(os.path.dirname(symlink_path), target))
    assert target == script_path, f"Symlink points to {target}, expected {script_path}"

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_obfuscator"
    agent_path = "/home/user/bin/obfuscate_stream"

    assert os.path.isfile(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.access(oracle_path, os.X_OK), f"Oracle not executable: {oracle_path}"

    random.seed(42)

    for i in range(200):
        length = random.randint(0, 8192)
        input_data = bytes(random.getrandbits(8) for _ in range(length))

        # Run oracle
        try:
            oracle_proc = subprocess.run(
                [oracle_path],
                input=input_data,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=2,
                check=True
            )
            oracle_out = oracle_proc.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on iteration {i} with length {length}: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on iteration {i} with length {length}")

        # Run agent
        try:
            agent_proc = subprocess.run(
                [agent_path],
                input=input_data,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=2
            )
            agent_out = agent_proc.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent timed out on iteration {i} with length {length}")
        except Exception as e:
            pytest.fail(f"Agent execution failed on iteration {i}: {e}")

        assert agent_proc.returncode == 0, f"Agent script returned non-zero exit code {agent_proc.returncode} on iteration {i}. Stderr: {agent_proc.stderr.decode(errors='replace')}"

        if oracle_out != agent_out:
            # truncate for display if too long
            disp_in = input_data[:32].hex() + ("..." if len(input_data) > 32 else "")
            disp_oracle = oracle_out[:32].hex() + ("..." if len(oracle_out) > 32 else "")
            disp_agent = agent_out[:32].hex() + ("..." if len(agent_out) > 32 else "")
            pytest.fail(
                f"Mismatch on iteration {i} (length {length}).\n"
                f"Input (hex): {disp_in}\n"
                f"Oracle out : {disp_oracle}\n"
                f"Agent out  : {disp_agent}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
