#!/bin/bash
set -e
mkdir -p /logs/verifier

# Prevent the submitted program from directly reading or executing the oracle.
ORACLE_PATH=/app/telemetry_obfuscator
ORIGINAL_MODE=$(stat -c '%a' "$ORACLE_PATH")
chmod 700 "$ORACLE_PATH"
trap 'chmod "$ORIGINAL_MODE" "$ORACLE_PATH" 2>/dev/null || true' EXIT

# Remove any oracle proxy the agent may have left running under its account.
pkill -KILL -u user 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import tempfile
import pytest

ORACLE_PATH = "/app/telemetry_obfuscator"
AGENT_PATH = "/home/user/py_obfuscator.py"
NUM_TESTS = 500
MAX_LEN = 2048

def test_agent_script_exists():
    assert os.path.exists(AGENT_PATH), f"Agent script not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Path {AGENT_PATH} is not a file"

def run_agent(input_data, test_number):
    with tempfile.NamedTemporaryFile(prefix="agent_exec_trace_", delete=False) as trace_file:
        trace_path = trace_file.name

    try:
        agent_proc = subprocess.run(
            [
                "strace", "-f", "-qq", "-e", "trace=execve",
                "-o", trace_path, "-u", "user",
                "python3", AGENT_PATH,
            ],
            input=input_data,
            capture_output=True,
            check=False,
        )

        with open(trace_path, "r", encoding="utf-8", errors="replace") as f:
            trace = f.read()

        # The one successful execve is strace starting the requested Python
        # interpreter. A wrapper that launches the oracle (or a copied binary)
        # necessarily produces another successful execve.
        successful_execs = [
            line for line in trace.splitlines()
            if "execve(" in line and line.rstrip().endswith("= 0")
        ]
        assert len(successful_execs) == 1, (
            f"Agent launched an external executable on test {test_number}; "
            f"the solution must implement the transformation in Python.\n"
            f"execve trace:\n{trace}"
        )
        return agent_proc
    finally:
        try:
            os.unlink(trace_path)
        except FileNotFoundError:
            pass

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary {ORACLE_PATH} is not executable"

    random.seed(42)

    for i in range(NUM_TESTS):
        length = random.randint(0, MAX_LEN)
        input_data = bytes(random.choices(range(256), k=length))

        # Run oracle
        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=input_data,
            capture_output=True,
            check=False
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on test {i} with length {length}"
        oracle_output = oracle_proc.stdout

        # Run agent as the unprivileged account while tracing process execution.
        agent_proc = run_agent(input_data, i)
        assert agent_proc.returncode == 0, f"Agent script failed on test {i} with length {length}. Stderr: {agent_proc.stderr.decode(errors='replace')}"
        agent_output = agent_proc.stdout

        if oracle_output != agent_output:
            # Provide a clear failure message
            input_hex = input_data.hex()
            if len(input_hex) > 100:
                input_hex = input_hex[:100] + "... (truncated)"

            oracle_hex = oracle_output.hex()
            if len(oracle_hex) > 100:
                oracle_hex = oracle_hex[:100] + "... (truncated)"

            agent_hex = agent_output.hex()
            if len(agent_hex) > 100:
                agent_hex = agent_hex[:100] + "... (truncated)"

            pytest.fail(
                f"Mismatch on test {i} (length {length}):\n"
                f"Input (hex): {input_hex}\n"
                f"Oracle output (hex): {oracle_hex}\n"
                f"Agent output (hex):  {agent_hex}\n"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
