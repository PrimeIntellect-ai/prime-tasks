#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import string
import pytest

ORACLE_PATH = "/tests/oracle_tracker"
AGENT_PATH = "/home/user/tracker/target/release/config-tracker"
FINAL_STATE_LOG = "/home/user/final_state.log"

def generate_random_input(seed):
    random.seed(seed)
    num_lines = random.randint(0, 500)
    lines = []
    ops = ["SET", "UPDATE", "DELETE", "INVALID"]

    for _ in range(num_lines):
        is_corrupt = random.random() < 0.20

        if is_corrupt:
            corruption_type = random.choice(["extra_spaces", "invalid_ts", "bad_key", "bad_cols"])
            if corruption_type == "extra_spaces":
                ts = random.randint(1000, 1010)
                op = random.choice(ops)
                key = "".join(random.choices(string.ascii_letters, k=5))
                val = "".join(random.choices(string.ascii_letters, k=5))
                lines.append(f"  {ts}   {op}  {key}   {val}  ")
            elif corruption_type == "invalid_ts":
                ts = "NOT_A_NUM"
                op = random.choice(ops)
                key = "".join(random.choices(string.ascii_letters, k=5))
                val = "".join(random.choices(string.ascii_letters, k=5))
                lines.append(f"{ts} {op} {key} {val}")
            elif corruption_type == "bad_key":
                ts = random.randint(1000, 1010)
                op = random.choice(ops)
                key = "bad-key!"
                val = "val"
                lines.append(f"{ts} {op} {key} {val}")
            else:
                lines.append("just some random junk")
        else:
            ts = random.randint(1000, 1010)
            op = random.choice(ops)
            key = "".join(random.choices(string.ascii_letters + string.digits + "_", k=random.randint(1, 10)))
            val = "".join(random.choices(string.ascii_letters + string.digits, k=random.randint(1, 10)))
            lines.append(f"{ts} {op} {key} {val}")

    return "\n".join(lines) + "\n"

def test_agent_binary_exists():
    assert os.path.isfile(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary at {AGENT_PATH} is not executable"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), "Oracle binary missing"
    assert os.path.isfile(AGENT_PATH), "Agent binary missing"

    for i in range(1000):
        input_data = generate_random_input(seed=42 + i)

        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=input_data,
            text=True,
            capture_output=True
        )

        agent_proc = subprocess.run(
            [AGENT_PATH],
            input=input_data,
            text=True,
            capture_output=True
        )

        oracle_out = oracle_proc.stdout
        agent_out = agent_proc.stdout

        if oracle_out != agent_out:
            pytest.fail(
                f"Mismatch on iteration {i}!\n\n"
                f"Input:\n{input_data}\n"
                f"Oracle Output:\n{oracle_out}\n"
                f"Agent Output:\n{agent_out}\n"
            )

def test_final_state_log():
    assert os.path.isfile(FINAL_STATE_LOG), f"Final state log not found at {FINAL_STATE_LOG}"
    with open(FINAL_STATE_LOG, "r") as f:
        content = f.read().strip()

    expected_content = """1000 => A=10, B=20
1001 => A=15
1002 => A=15, C=30"""

    assert content == expected_content, f"Final state log content does not match expected.\nExpected:\n{expected_content}\nGot:\n{content}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
