#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import json
import random
import subprocess
import pytest

def test_tracker_exists_and_executable():
    """Verify the compiled tracker binary exists and is executable."""
    tracker_path = "/home/user/tracker"
    assert os.path.isfile(tracker_path), f"The binary {tracker_path} is missing."
    st = os.stat(tracker_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"The binary {tracker_path} is not executable."

def test_vendored_package_is_fixed():
    """Verify the deliberate perturbation in gjson.go has been fixed."""
    with open("/app/gjson/gjson.go", "r") as f:
        content = f.read()
    assert "return 0 // DELIBERATELY BROKEN" not in content, "The deliberate perturbation in gjson.go was not fixed."

def generate_fuzz_input(seed):
    """Generate a random JSONL stream based on the fuzz distribution."""
    random.seed(seed)
    num_lines = random.randint(50, 5000)
    hosts = ["web-1", "web-2", "db-1", "cache-1"]
    metrics = ["cpu", "mem", "timeout"]

    lines = []
    for _ in range(num_lines):
        record = {
            "host": random.choice(hosts),
            "metric": random.choice(metrics),
            "ts": random.randint(0, 5000),
            "val": round(random.uniform(0.0, 100.0), 4)
        }
        lines.append(json.dumps(record))
    return "\n".join(lines) + "\n"

@pytest.mark.parametrize("seed", range(100))
def test_fuzz_equivalence(seed):
    """Run the agent's tracker and the oracle on random inputs and compare outputs."""
    tracker_path = "/home/user/tracker"
    oracle_path = "/tests/tracker_oracle"

    input_data = generate_fuzz_input(seed)

    agent_proc = subprocess.run(
        [tracker_path],
        input=input_data,
        text=True,
        capture_output=True
    )
    assert agent_proc.returncode == 0, f"Agent program failed with stderr:\n{agent_proc.stderr}"
    agent_output = agent_proc.stdout

    oracle_proc = subprocess.run(
        [oracle_path],
        input=input_data,
        text=True,
        capture_output=True
    )
    assert oracle_proc.returncode == 0, f"Oracle program failed with stderr:\n{oracle_proc.stderr}"
    oracle_output = oracle_proc.stdout

    if agent_output != oracle_output:
        input_snippet = input_data[:500] + "\n... (truncated)" if len(input_data) > 500 else input_data
        agent_snippet = agent_output[:500] + "\n... (truncated)" if len(agent_output) > 500 else agent_output
        oracle_snippet = oracle_output[:500] + "\n... (truncated)" if len(oracle_output) > 500 else oracle_output

        pytest.fail(
            f"Output mismatch on fuzz seed {seed}.\n\n"
            f"Input snippet:\n{input_snippet}\n\n"
            f"Oracle output snippet:\n{oracle_snippet}\n\n"
            f"Agent output snippet:\n{agent_snippet}\n"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
