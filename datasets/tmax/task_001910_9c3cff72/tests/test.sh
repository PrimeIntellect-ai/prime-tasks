#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess

N = 5000
MIN_LEN = 4
MAX_LEN = 256
ORACLE = "/app/oracle_decoder"
AGENT_SCRIPT = "/home/user/clean_decoder.py"


def test_agent_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"{AGENT_SCRIPT} is not executable"


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE), f"Oracle not found at {ORACLE}"
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"

    random.seed(42)

    inputs = []
    for _ in range(N):
        length = random.randint(MIN_LEN, MAX_LEN)
        inputs.append(bytes(random.choices(range(256), k=length)))

    for l_val in [2, 3, 4, 5, 10, 100]:
        payload_len = max(l_val, 0)
        if payload_len + 4 <= MAX_LEN:
            prefix = l_val.to_bytes(4, byteorder="little", signed=True)
            body = bytes(random.choices(range(256), k=payload_len))
            inputs.append(prefix + body)

    oracle_results = []
    try:
        for input_data in inputs:
            proc = subprocess.run(
                [ORACLE],
                input=input_data,
                capture_output=True,
            )
            oracle_results.append((proc.returncode, proc.stdout))
    finally:
        # The agent was allowed to inspect the challenge binary, but it must not
        # be available for delegation while the submitted implementation runs.
        if os.path.lexists(ORACLE):
            os.unlink(ORACLE)

    for idx, (input_data, expected) in enumerate(zip(inputs, oracle_results)):
        agent_proc = subprocess.run(
            ["python3", AGENT_SCRIPT],
            input=input_data,
            capture_output=True,
        )

        oracle_returncode, oracle_stdout = expected
        msg_base = f"Mismatch on input #{idx} (hex: {input_data.hex()})"
        assert oracle_returncode == agent_proc.returncode, (
            f"{msg_base}: Return code oracle={oracle_returncode}, "
            f"agent={agent_proc.returncode}"
        )
        assert oracle_stdout == agent_proc.stdout, (
            f"{msg_base}: Stdout oracle={oracle_stdout.hex()}, "
            f"agent={agent_proc.stdout.hex()}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
