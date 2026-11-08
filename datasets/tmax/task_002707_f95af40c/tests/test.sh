#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import time

def test_fuzz_equivalence():
    agent_script = "/home/user/process_logs.sh"
    oracle_script = "/tests/oracle.sh"

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script not found at {oracle_script}"

    # Generate 500 lines of fuzz input
    random.seed(42)
    start_ts = 946684800  # 2000-01-01T00:00:00Z
    end_ts = 1924991999   # 2030-12-31T23:59:59Z

    lines = []
    for _ in range(500):
        # 10% chance of generating an invalid timestamp format to test filtering
        if random.random() < 0.1:
            ts_str = "INVALID_TIMESTAMP"
        else:
            ts = random.randint(start_ts, end_ts)
            ts_str = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(ts))

        num_bytes = random.randint(10, 80)
        rand_bytes = bytes(random.choices(range(256), k=num_bytes))

        line = ts_str.encode('ascii') + b' ' + rand_bytes
        lines.append(line)

    fuzz_input = b'\n'.join(lines) + b'\n'

    # Run oracle
    oracle_proc = subprocess.run(
        ["bash", oracle_script],
        input=fuzz_input,
        capture_output=True
    )
    oracle_out = oracle_proc.stdout

    # Run agent
    agent_proc = subprocess.run(
        ["bash", agent_script],
        input=fuzz_input,
        capture_output=True
    )
    agent_out = agent_proc.stdout

    if oracle_out != agent_out:
        # Find the first differing line for a helpful error message
        oracle_lines = oracle_out.split(b'\n')
        agent_lines = agent_out.split(b'\n')

        max_lines = max(len(oracle_lines), len(agent_lines))
        for i in range(max_lines):
            o_line = oracle_lines[i] if i < len(oracle_lines) else b"<EOF>"
            a_line = agent_lines[i] if i < len(agent_lines) else b"<EOF>"
            if o_line != a_line:
                error_msg = (
                    f"Output mismatch at line {i+1}.\n"
                    f"Oracle output: {o_line!r}\n"
                    f"Agent output:  {a_line!r}\n"
                )
                assert False, error_msg

    assert oracle_out == agent_out, "Agent output does not match oracle output exactly."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
