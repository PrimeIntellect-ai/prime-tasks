#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def generate_fuzz_input(seed):
    random.seed(seed)
    num_lines = random.randint(5, 500)
    lines = []
    for _ in range(num_lines):
        cols = []
        for _ in range(3):
            r = random.random()
            if r < 0.1:
                cols.append("NaN")
            elif r < 0.2:
                # Value out of bounds (> 1000.0 or < -1000.0)
                val = random.uniform(1000.1, 5000.0)
                if random.choice([True, False]):
                    val = -val
                cols.append(f"{val:.4f}")
            else:
                # Valid value
                val = random.uniform(-1000.0, 1000.0)
                cols.append(f"{val:.4f}")
        lines.append(",".join(cols))
    return "\n".join(lines) + "\n"

def test_fuzz_equivalence():
    """Fuzz the agent's binary against the oracle binary."""
    agent_bin = "/home/user/process_data"
    oracle_bin = "/tests/oracle_correlate"

    assert os.path.isfile(agent_bin), f"Agent binary not found at {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"Agent binary is not executable at {agent_bin}"
    assert os.path.isfile(oracle_bin), f"Oracle binary not found at {oracle_bin}"

    for i in range(200):
        input_data = generate_fuzz_input(seed=i)

        agent_proc = subprocess.run([agent_bin], input=input_data, text=True, capture_output=True)
        oracle_proc = subprocess.run([oracle_bin], input=input_data, text=True, capture_output=True)

        assert agent_proc.stdout == oracle_proc.stdout, (
            f"stdout mismatch on iteration {i}\n"
            f"Input:\n{input_data[:200]}...\n"
            f"Oracle stdout:\n{oracle_proc.stdout}\n"
            f"Agent stdout:\n{agent_proc.stdout}"
        )
        assert agent_proc.stderr == oracle_proc.stderr, (
            f"stderr mismatch on iteration {i}\n"
            f"Input:\n{input_data[:200]}...\n"
            f"Oracle stderr:\n{oracle_proc.stderr}\n"
            f"Agent stderr:\n{agent_proc.stderr}"
        )
        assert agent_proc.returncode == oracle_proc.returncode, (
            f"Return code mismatch on iteration {i}: Oracle={oracle_proc.returncode}, Agent={agent_proc.returncode}"
        )

def test_fastcovar_fixed():
    """Verify that the bug in fastcovar.h was fixed."""
    header_path = "/app/fastcovar-0.3/include/fastcovar.h"
    assert os.path.isfile(header_path), f"{header_path} is missing"

    with open(header_path, "r") as f:
        content = f.read()

    assert "typedef double scalar_t;" in content, "The bug 'typedef int scalar_t;' was not changed to 'typedef double scalar_t;' in fastcovar.h"
    assert "typedef int scalar_t;" not in content, "The bug 'typedef int scalar_t;' is still present in fastcovar.h"

def test_fastcovar_compiled():
    """Verify that the fastcovar library was compiled."""
    lib_path = "/app/fastcovar-0.3/lib/libfastcovar.a"
    assert os.path.isfile(lib_path), f"Compiled library not found at {lib_path}. Did you run make?"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
