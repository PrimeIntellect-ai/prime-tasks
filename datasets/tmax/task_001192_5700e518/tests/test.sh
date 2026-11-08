#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

ORACLE_CPP = """#include <iostream>
#include <iomanip>
#include <algorithm>

int main() {
    double x1, x2, x3;
    if (!(std::cin >> x1 >> x2 >> x3)) return 1;

    double y1 = 1.5 * x1 + (-0.5) * x2 + 0.0 * x3 + 0.1;
    double y2 = 0.0 * x1 + 2.0 * x2 + (-1.0) * x3 + (-0.5);

    y1 = std::max(-5.0, std::min(5.0, y1));
    y2 = std::max(-5.0, std::min(5.0, y2));

    std::cout << std::fixed << std::setprecision(4) << y1 << " " << y2 << "\\n";
    return 0;
}
"""

@pytest.fixture(scope="session", autouse=True)
def setup_oracle():
    oracle_src = "/tmp/oracle_transform.cpp"
    oracle_bin = "/app/oracle_transform"

    with open(oracle_src, "w") as f:
        f.write(ORACLE_CPP)

    compile_cmd = ["g++", "-O3", oracle_src, "-o", oracle_bin]
    subprocess.run(compile_cmd, check=True)

    yield

    if os.path.exists(oracle_src):
        os.remove(oracle_src)
    if os.path.exists(oracle_bin):
        os.remove(oracle_bin)

def test_agent_binary_exists():
    agent_bin = "/home/user/transform"
    assert os.path.isfile(agent_bin), f"Agent binary not found at {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"Agent binary at {agent_bin} is not executable"

def test_fuzz_equivalence():
    agent_bin = "/home/user/transform"
    oracle_bin = "/app/oracle_transform"

    assert os.path.isfile(agent_bin), "Agent binary does not exist."
    assert os.path.isfile(oracle_bin), "Oracle binary does not exist."

    random.seed(42)
    num_iterations = 500

    for i in range(num_iterations):
        x1 = random.uniform(-20.0, 20.0)
        x2 = random.uniform(-20.0, 20.0)
        x3 = random.uniform(-20.0, 20.0)

        input_str = f"{x1} {x2} {x3}\n"

        oracle_proc = subprocess.run(
            [oracle_bin],
            input=input_str,
            text=True,
            capture_output=True,
            check=True
        )
        oracle_out = oracle_proc.stdout.strip()

        agent_proc = subprocess.run(
            [agent_bin],
            input=input_str,
            text=True,
            capture_output=True
        )

        assert agent_proc.returncode == 0, f"Agent binary crashed on input: {input_str.strip()}\nStderr: {agent_proc.stderr}"

        agent_out = agent_proc.stdout.strip()

        assert agent_out == oracle_out, (
            f"Mismatch on input: {input_str.strip()}\n"
            f"Expected (Oracle): '{oracle_out}'\n"
            f"Got (Agent)      : '{agent_out}'"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
