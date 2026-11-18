#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

def generate_fuzz_input(seed):
    random.seed(seed)

    rows = random.randint(50, 200)
    cols = 10

    lines = []
    for _ in range(rows):
        row_vals = []
        for _ in range(cols):
            if random.random() < 0.10:
                row_vals.append("")
            else:
                val = random.gauss(0, 10)
                if random.random() < 0.05:
                    val *= 10
                row_vals.append(str(val))
        lines.append(",".join(row_vals))

    return "\n".join(lines)

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_pipeline.py"
    agent_path = "/home/user/pipeline.py"

    assert os.path.isfile(oracle_path), f"Oracle script not found at {oracle_path}"
    assert os.path.isfile(agent_path), f"Agent script not found at {agent_path}"

    for i in range(100):
        input_data = generate_fuzz_input(i)

        oracle_proc = subprocess.run(
            ["python3", oracle_path],
            input=input_data,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}:\n{oracle_proc.stderr}"

        agent_proc = subprocess.run(
            ["python3", agent_path],
            input=input_data,
            text=True,
            capture_output=True
        )
        assert agent_proc.returncode == 0, f"Agent failed on iteration {i}:\n{agent_proc.stderr}"

        if oracle_proc.stdout != agent_proc.stdout:
            pytest.fail(
                f"Output mismatch on iteration {i}.\n"
                f"Input (first 3 lines):\n{chr(10).join(input_data.split(chr(10))[:3])}\n...\n"
                f"Oracle Output:\n{oracle_proc.stdout}\n"
                f"Agent Output:\n{agent_proc.stdout}"
            )

def test_plot_cov_generates_image():
    plot_script = "/home/user/plot_cov.py"
    plot_output = "/home/user/cov_plot.png"

    assert os.path.isfile(plot_script), f"Plot script not found at {plot_script}"

    if os.path.exists(plot_output):
        os.remove(plot_output)

    proc = subprocess.run(["python3", plot_script], capture_output=True, text=True)
    assert proc.returncode == 0, f"plot_cov.py failed to run:\n{proc.stderr}"

    assert os.path.isfile(plot_output), f"Expected plot file {plot_output} was not generated."

    # Check if the image has a reasonable size to not be completely empty/corrupt
    size = os.path.getsize(plot_output)
    assert size > 100, f"Generated plot {plot_output} is suspiciously small ({size} bytes), likely blank."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
