#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import random
import subprocess
import time
import socket
import pytest

def test_env_configs_fixed():
    """Verify that the environment variables are correctly set in the config files."""
    def parse_env(filepath):
        env_vars = {}
        with open(filepath, "r") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    key, val = line.split("=", 1)
                    env_vars[key.strip()] = val.strip().strip("'\"")
        return env_vars

    api_env = parse_env("/app/config/api.env")
    assert api_env.get("REDIS_HOST") == "127.0.0.1", "REDIS_HOST not correctly set in api.env"
    assert api_env.get("REDIS_PORT") == "6379", "REDIS_PORT not correctly set in api.env"

    archiver_env = parse_env("/app/config/archiver.env")
    assert archiver_env.get("REDIS_HOST") == "127.0.0.1", "REDIS_HOST not correctly set in archiver.env"
    assert archiver_env.get("REDIS_PORT") == "6379", "REDIS_PORT not correctly set in archiver.env"
    assert archiver_env.get("OUTPUT_FILE") == "/app/data/raw_sensors.csv", "OUTPUT_FILE not correctly set in archiver.env"

def test_redis_running():
    """Check if Redis is listening on the expected port."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.connect(("127.0.0.1", 6379))
        s.close()
    except Exception:
        pytest.fail("Redis server is not running or not listening on 127.0.0.1:6379")

def test_pipeline_end_to_end():
    """Verify that the end-to-end pipeline works by briefly running the continuous generator."""
    output_file = "/app/data/raw_sensors.csv"
    initial_size = os.path.getsize(output_file) if os.path.exists(output_file) else 0

    generator = None
    try:
        generator = subprocess.Popen(
            ["python3", "/app/generator.py"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        time.sleep(3)
    except Exception as e:
        pytest.fail(f"Failed to run generator.py: {e}")
    finally:
        if generator is not None and generator.poll() is None:
            generator.terminate()
            try:
                generator.wait(timeout=2)
            except subprocess.TimeoutExpired:
                generator.kill()
                generator.wait()

    # Give the pipeline a moment to process the messages
    time.sleep(2)

    assert os.path.exists(output_file), f"Archiver output file {output_file} was not created."
    new_size = os.path.getsize(output_file)
    assert new_size > initial_size, "No new data was written to raw_sensors.csv. The pipeline is not functioning end-to-end."

def test_processor_fuzz_equivalence():
    """Fuzz test the agent's processor script against the reference oracle."""
    oracle_script = "/app/oracle_processor.py"
    agent_script = "/home/user/process_metrics.py"
    metadata_file = "/app/data/metadata.csv"

    assert os.path.exists(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.exists(oracle_script), f"Oracle script not found at {oracle_script}"

    random.seed(1337)
    num_fuzz_tests = 100

    for i in range(num_fuzz_tests):
        num_rows = random.randint(10, 500)
        input_csv_path = f"/tmp/fuzz_input_{i}.csv"

        with open(input_csv_path, "w") as f:
            f.write("timestamp,sensor_A,sensor_B,sensor_C\n")
            ts = 1600000000
            for _ in range(num_rows):
                ts += random.randint(1, 10)
                row_vals = []
                for _ in range(3):
                    if random.random() < 0.1:
                        row_vals.append("")
                    else:
                        row_vals.append(f"{random.uniform(10.0, 99.9):.2f}")
                f.write(f"{ts},{row_vals[0]},{row_vals[1]},{row_vals[2]}\n")

        # Run oracle
        oracle_cmd = ["python3", oracle_script, input_csv_path, metadata_file]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on iteration {i}:\n{oracle_res.stderr}"

        # Run agent
        agent_cmd = ["python3", agent_script, input_csv_path, metadata_file]
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent script failed on iteration {i}:\n{agent_res.stderr}"

        try:
            oracle_output = json.loads(oracle_res.stdout)
        except json.JSONDecodeError:
            pytest.fail(f"Oracle output is not valid JSON on iteration {i}")

        try:
            agent_output = json.loads(agent_res.stdout)
        except json.JSONDecodeError:
            pytest.fail(f"Agent output is not valid JSON on iteration {i}:\n{agent_res.stdout}")

        assert agent_output == oracle_output, (
            f"Output mismatch on fuzz iteration {i}.\n"
            f"Input file: {input_csv_path}\n"
            f"Oracle output length: {len(oracle_output)}\n"
            f"Agent output length: {len(agent_output)}\n"
            f"Agent Output: {agent_output[:2]}...\n"
            f"Oracle Output: {oracle_output[:2]}..."
        )

        os.remove(input_csv_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
