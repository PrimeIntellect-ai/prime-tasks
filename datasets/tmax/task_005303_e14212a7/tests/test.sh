#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import random
import subprocess
import pytest

AGENT_EXE = "/home/user/audit_checker"
ORACLE_EXE = "/tests/oracle_audit_checker"
NUM_RUNS = 50

def generate_fuzz_input(seed: int) -> str:
    """Generates random JSON lines for testing based on the specified distribution."""
    random.seed(seed)
    num_lines = random.randint(10, 500)
    accounts = [f"acc_{i}" for i in range(10)]

    data = []
    used_times = {acc: set() for acc in accounts}

    for _ in range(num_lines):
        acc = random.choice(accounts)
        while True:
            t = random.randint(1000000, 2000000)
            if t not in used_times[acc]:
                used_times[acc].add(t)
                break
        amt = round(random.uniform(10.0, 1000.0), 2)
        data.append({"account_id": acc, "tx_time": t, "amount": amt})

    random.shuffle(data)
    return "\n".join(json.dumps(d) for d in data) + "\n"

def run_executable(exe_path: str, input_data: str):
    """Runs the given executable with the provided stdin data."""
    try:
        result = subprocess.run(
            [exe_path],
            input=input_data,
            text=True,
            capture_output=True,
            timeout=5
        )
        return result.stdout, result.stderr, result.returncode
    except subprocess.TimeoutExpired:
        return "", "Execution timed out", -1
    except Exception as e:
        return "", str(e), -1

def compare_outputs(oracle_out: str, agent_out: str):
    """Compares the outputs line by line, parsing as JSON to ignore formatting differences."""
    oracle_lines = [l.strip() for l in oracle_out.strip().split('\n') if l.strip()]
    agent_lines = [l.strip() for l in agent_out.strip().split('\n') if l.strip()]

    if len(oracle_lines) != len(agent_lines):
        return False, f"Line count mismatch: Oracle={len(oracle_lines)}, Agent={len(agent_lines)}"

    for i, (ol, al) in enumerate(zip(oracle_lines, agent_lines)):
        try:
            o_json = json.loads(ol)
            a_json = json.loads(al)
            if o_json != a_json:
                return False, f"JSON mismatch at line {i+1}:\nOracle: {o_json}\nAgent: {a_json}"
        except json.JSONDecodeError:
            if ol != al:
                return False, f"Text mismatch at line {i+1} (invalid JSON):\nOracle: {ol}\nAgent: {al}"

    return True, ""

def test_agent_executable_exists():
    """Verify that the agent has compiled the Rust program to the correct location."""
    assert os.path.isfile(AGENT_EXE), f"Agent executable not found at {AGENT_EXE}"
    assert os.access(AGENT_EXE, os.X_OK), f"Agent file at {AGENT_EXE} is not executable"

def test_fuzz_equivalence():
    """Run fuzz equivalence testing between the oracle and the agent's executable."""
    assert os.path.isfile(ORACLE_EXE), f"Oracle executable missing at {ORACLE_EXE}"

    for i in range(NUM_RUNS):
        input_data = generate_fuzz_input(seed=42 + i)

        oracle_stdout, oracle_stderr, oracle_rc = run_executable(ORACLE_EXE, input_data)
        agent_stdout, agent_stderr, agent_rc = run_executable(AGENT_EXE, input_data)

        assert agent_rc == oracle_rc, (
            f"Return code mismatch on run {i+1}.\n"
            f"Oracle returned {oracle_rc}, Agent returned {agent_rc}\n"
            f"Agent stderr: {agent_stderr}"
        )

        match, error_msg = compare_outputs(oracle_stdout, agent_stdout)
        if not match:
            pytest.fail(
                f"Output mismatch on run {i+1}!\n\n"
                f"Input (first 5 lines):\n"
                f"{''.join(input_data.splitlines(True)[:5])}...\n\n"
                f"Detail:\n{error_msg}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
