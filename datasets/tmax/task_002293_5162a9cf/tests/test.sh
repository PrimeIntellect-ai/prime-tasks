#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import tempfile
import random
import csv
import pytest

def test_fuzz_equivalence():
    agent_script = "/home/user/pipeline.py"
    oracle_script = "/tests/oracle_pipeline.py"
    sample_wav = "/app/sample.wav"

    assert os.path.isfile(agent_script), f"Agent script missing: {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script missing: {oracle_script}"
    assert os.path.isfile(sample_wav), f"Sample wav missing: {sample_wav}"

    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(20):
            num_rows = random.randint(10, 100)
            input_csv = os.path.join(tmpdir, f"input_{i}.csv")
            agent_out = os.path.join(tmpdir, f"agent_out_{i}.csv")
            oracle_out = os.path.join(tmpdir, f"oracle_out_{i}.csv")

            ids = list(range(1, num_rows + 1))
            random.shuffle(ids)

            splits = ["train", "train"] + [random.choice(["train", "test"]) for _ in range(num_rows - 2)]
            random.shuffle(splits)

            with open(input_csv, 'w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(["id", "split", "audio_path", "f1", "f2"])
                for j in range(num_rows):
                    writer.writerow([
                        ids[j],
                        splits[j],
                        sample_wav,
                        random.uniform(-1000.0, 1000.0),
                        random.uniform(-1000.0, 1000.0)
                    ])

            # Run oracle
            res_oracle = subprocess.run(
                ["python3", oracle_script, input_csv, oracle_out],
                capture_output=True, text=True
            )
            assert res_oracle.returncode == 0, f"Oracle failed on input {i}:\n{res_oracle.stderr}"

            # Run agent
            res_agent = subprocess.run(
                ["python3", agent_script, input_csv, agent_out],
                capture_output=True, text=True
            )
            assert res_agent.returncode == 0, f"Agent script failed on input {i}:\n{res_agent.stderr}"

            # Compare outputs
            assert os.path.isfile(oracle_out), f"Oracle did not produce output for input {i}"
            assert os.path.isfile(agent_out), f"Agent did not produce output for input {i}"

            with open(oracle_out, 'r') as f:
                oracle_data = f.read()
            with open(agent_out, 'r') as f:
                agent_data = f.read()

            if oracle_data != agent_data:
                with open(input_csv, 'r') as f:
                    input_data = f.read()
                pytest.fail(
                    f"Output mismatch on fuzz iteration {i}.\n\n"
                    f"--- Input CSV ---\n{input_data}\n"
                    f"--- Expected Output (Oracle) ---\n{oracle_data}\n"
                    f"--- Actual Output (Agent) ---\n{agent_data}"
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
