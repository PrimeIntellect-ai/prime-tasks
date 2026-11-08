#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest
from concurrent.futures import ThreadPoolExecutor

AGENT_SCRIPT = "/home/user/clean_calc.py"
ORACLE_BINARY = "/app/calc_service_stripped"

def run_cmd(cmd, stdin_input=None):
    try:
        result = subprocess.run(
            cmd,
            input=stdin_input,
            capture_output=True,
            text=True,
            timeout=2,
        )
        return result.stdout.strip(), result.stderr.strip(), result.returncode
    except subprocess.TimeoutExpired:
        return "TIMEOUT", "", -1

def test_agent_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} not found."
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file."

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_BINARY), f"Oracle binary {ORACLE_BINARY} missing."

    random.seed(42)
    inputs = []
    for _ in range(1000):  # Using 1000 to avoid test timeout while maintaining robustness
        x = random.randint(1, 4)  # Keeping X small to prevent Ackermann-like explosion timeouts
        y = random.randint(1, 20)
        inputs.append(f"SEQ[{x},{y}]")

    def check_input(inp):
        oracle_out, _, oracle_rc = run_cmd([ORACLE_BINARY], stdin_input=inp)
        agent_out, _, agent_rc = run_cmd(["python3", AGENT_SCRIPT, inp])

        # If oracle crashes on valid input, we skip (though it shouldn't for these)
        if oracle_rc != 0 and oracle_out == "":
            return None

        return inp, oracle_out, agent_out

    with ThreadPoolExecutor(max_workers=16) as executor:
        results = list(executor.map(check_input, inputs))

    for res in results:
        if res is None:
            continue
        inp, oracle_out, agent_out = res
        assert agent_out == oracle_out, f"Mismatch on input {inp}: Oracle='{oracle_out}', Agent='{agent_out}'"

def test_invalid_formats():
    invalid_inputs = [
        "SEQ1,2]",
        "SEQ[1,2",
        "SEQ[-1,2]",
        "SEQ[1,-2]",
        "SEQ[A,2]",
        "OP[1,2]",
        "SEQ[1 2]",
        "SEQ[]"
    ]

    for inp in invalid_inputs:
        agent_out, _, agent_rc = run_cmd(["python3", AGENT_SCRIPT, inp])
        assert agent_out == "INVALID_FORMAT", f"Expected 'INVALID_FORMAT' for input '{inp}', got '{agent_out}'"
        assert agent_rc == 0, f"Expected exit code 0 for invalid format input '{inp}', got {agent_rc}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
