#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sys
import subprocess
from pathlib import Path
import numpy as np

def generate_test_data():
    np.random.seed(42)
    return np.random.uniform(-100, 100, 1000)

def run_program(executable, data, env=None):
    input_str = "\n".join(map(str, data)) + "\n"
    res = subprocess.run(
        [executable],
        input=input_str,
        text=True,
        capture_output=True,
        env=env
    )
    if res.returncode != 0:
        raise RuntimeError(f"Error running {executable}: {res.stderr}")

    output = res.stdout.strip().split("\n")
    if len(output) != len(data):
        raise ValueError(f"Expected {len(data)} output lines, got {len(output)}")

    return np.array([float(x) for x in output])

def test_pipeline_fixed_exists():
    path = Path("/home/user/sensor_pipeline/pipeline_fixed")
    assert path.is_file(), "/home/user/sensor_pipeline/pipeline_fixed binary is missing"
    assert os.access(path, os.X_OK), "/home/user/sensor_pipeline/pipeline_fixed is not executable"

def test_mse_metric_threshold():
    pipeline_fixed = "/home/user/sensor_pipeline/pipeline_fixed"
    legacy_oracle = "/app/legacy_oracle"

    assert os.path.exists(pipeline_fixed), f"{pipeline_fixed} not found."
    assert os.path.exists(legacy_oracle), f"{legacy_oracle} not found."

    data = generate_test_data()

    env = os.environ.copy()
    env["ORACLE_KEY"] = "KEY_A9F3B2C8D7E1"

    try:
        oracle_out = run_program(legacy_oracle, data, env=env)
    except Exception as e:
        assert False, f"Failed to run legacy oracle: {e}"

    try:
        agent_out = run_program(pipeline_fixed, data)
    except Exception as e:
        assert False, f"Failed to run pipeline_fixed: {e}"

    mse = np.mean((oracle_out - agent_out) ** 2)
    threshold = 1e-8

    assert mse <= threshold, f"MSE {mse} is greater than threshold {threshold}. Precision loss or logic bug not fully fixed."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
