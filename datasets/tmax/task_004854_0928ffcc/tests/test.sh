#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import string


def generate_fuzz_inputs(n=1000):
    random.seed(42)
    pool = ["DEBUG", "BETA", "PROD", "INFO", "WARN", "SYS"]
    lines = []
    for _ in range(n):
        num_words = random.randint(0, 6)
        words = []
        for _ in range(num_words):
            if random.random() < 0.5:
                words.append(random.choice(pool))
            else:
                word_len = random.randint(1, 10)
                words.append(''.join(random.choices(string.ascii_letters + string.digits, k=word_len)))

        line = ""
        for w in words:
            line += " " * random.randint(1, 3) + w
        line += " " * random.randint(0, 2)

        if len(line) < 10:
            line += " " * (10 - len(line))

        lines.append(line)
    return lines


def test_fuzz_equivalence():
    agent_source = "/home/user/parser.cpp"
    agent_bin = "/home/user/log_parser"
    oracle_bin = "/tests/ref_parser"

    assert os.path.isfile(agent_source), f"Agent source not found at {agent_source}"
    assert os.path.isfile(agent_bin), f"Agent binary not found at {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"Agent binary {agent_bin} is not executable"
    assert os.path.isfile(oracle_bin), f"Oracle binary not found at {oracle_bin}"
    assert os.access(oracle_bin, os.X_OK), f"Oracle binary {oracle_bin} is not executable"

    input_lines = generate_fuzz_inputs(1000)
    inputs_str = "\n".join(input_lines) + "\n"

    proc_oracle = subprocess.run([oracle_bin], input=inputs_str, text=True, capture_output=True)
    assert proc_oracle.returncode == 0, "Oracle binary failed to execute"

    proc_agent = subprocess.run([agent_bin], input=inputs_str, text=True, capture_output=True)

    if proc_agent.returncode != 0:
        assert False, f"Agent binary failed with return code {proc_agent.returncode}\nStderr: {proc_agent.stderr}"

    if proc_oracle.stdout != proc_agent.stdout:
        for line in input_lines:
            line_input = line + "\n"
            o_out = subprocess.run([oracle_bin], input=line_input, text=True, capture_output=True).stdout
            a_out = subprocess.run([agent_bin], input=line_input, text=True, capture_output=True).stdout

            if o_out != a_out:
                assert False, (
                    f"Mismatch found!\n"
                    f"Input line: {repr(line)}\n"
                    f"Expected output (Oracle): {repr(o_out)}\n"
                    f"Actual output (Agent): {repr(a_out)}"
                )

        assert False, "Outputs mismatched, but line-by-line check did not isolate the error. Check EOF handling."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
