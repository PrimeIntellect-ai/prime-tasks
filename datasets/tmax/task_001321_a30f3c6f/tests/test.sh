#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import string
import subprocess
import pytest

def generate_random_csv(seed):
    random.seed(seed)
    num_rows = random.randint(1, 10)
    lines = ["event_id,frame_idx"]
    for _ in range(num_rows):
        event_id = "evt_" + "".join(random.choices(string.ascii_letters + string.digits, k=random.randint(5, 8)))

        prob = random.random()
        if prob < 0.30:
            frame_idx_str = ""
        else:
            frame_idx = random.randint(0, 80)
            if prob < 0.40: # 10% probability
                frame_idx_str = f"{frame_idx}.0"
            else:
                frame_idx_str = str(frame_idx)

        lines.append(f"{event_id},{frame_idx_str}")

    return "\n".join(lines) + "\n"

def test_fuzz_equivalence():
    agent_script = "/home/user/pipeline.sh"
    oracle_script = "/tests/pipeline_oracle.sh"
    video_path = "/app/experiment_video.mp4"

    assert os.path.exists(agent_script), f"Agent script not found at {agent_script}"
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable"
    assert os.path.isfile(oracle_script), f"Oracle not found at {oracle_script}"

    N = 20
    for i in range(N):
        csv_input = generate_random_csv(seed=42 + i)

        # Run oracle
        oracle_proc = subprocess.run(
            ["bash", oracle_script, video_path],
            input=csv_input,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i} with error: {oracle_proc.stderr}"

        # Run agent
        agent_proc = subprocess.run(
            [agent_script, video_path],
            input=csv_input,
            text=True,
            capture_output=True
        )

        assert agent_proc.returncode == 0, f"Agent script failed on iteration {i}. Stderr: {agent_proc.stderr}\nInput:\n{csv_input}"

        oracle_out = oracle_proc.stdout
        agent_out = agent_proc.stdout

        if oracle_out != agent_out:
            pytest.fail(
                f"Output mismatch on iteration {i}.\n"
                f"Input CSV:\n{csv_input}\n"
                f"Expected (Oracle):\n{oracle_out}\n"
                f"Got (Agent):\n{agent_out}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
