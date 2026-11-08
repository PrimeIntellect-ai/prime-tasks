#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
from pathlib import Path
import os
import subprocess
import tempfile
import pytest

ORIGINAL_ARTIFACTS = b'''run_id,accuracy,loss,latency_ms
run_001,0.92,0.11,45.2
run_002,0.88,0.15,N/A
run_003,0.95,0.08,50.1
run_004,0.70,0.45,30.0
run_invalid_1,0.99,0.01
run_005,0.91,0.12,44.4
run_006,0.89,0.16,42.1
run_007,0.94,0.09,48.9
run_008,0.85,0.20,35.5
run_009,0.96,0.07,52.3
run_010,0.93,0.10,47.0
run_011,0.87,0.18,39.8
run_012,0.82,0.25,32.1
run_013,0.98,0.05,55.0
run_014,0.90,0.13,43.2
run_015,0.86,0.19,38.5
run_016,0.97,0.06,53.4
run_017,0.84,0.22,34.2
run_invalid_2,0.90,error,40.0
run_018,0.91,0.11,45.0
run_019,0.88,0.15,41.1
run_020,0.95,0.08,49.5
run_021,0.75,0.35,31.5
run_022,0.92,0.12,46.2
run_023,0.89,0.16,42.8
run_024,0.94,0.09,48.1
run_025,0.85,0.20,36.0
run_026,0.96,0.07,51.5
run_027,0.93,0.10,47.8
run_028,0.87,0.18,40.5
run_029,0.83,0.24,33.0
run_030,0.98,0.05,54.2
run_031,0.90,0.14,43.8
run_032,0.86,0.19,39.0
run_033,0.97,0.06,52.8
run_034,0.84,0.22,34.8
run_035,0.91,0.12,45.5
run_036,0.88,0.16,41.8
run_037,0.95,0.08,49.9
run_038,0.78,0.30,32.5
run_039,0.92,0.11,46.8
run_040,0.89,0.15,42.5
'''
ORIGINAL_SEED = b'my_fixed_random_seed_for_shuf_12345\n'


def test_input_fixtures_unchanged():
    """Reject attempts to alter the dataset or random source used by the task."""
    assert Path('/home/user/artifacts.csv').read_bytes() == ORIGINAL_ARTIFACTS, (
        '/home/user/artifacts.csv was modified.'
    )
    assert Path('/home/user/random_seed').read_bytes() == ORIGINAL_SEED, (
        '/home/user/random_seed was modified.'
    )


def test_evaluation_summary_exists():
    """Check if the evaluation summary file was created."""
    summary_path = '/home/user/evaluation_summary.txt'
    assert os.path.isfile(summary_path), f"File {summary_path} does not exist."


def test_evaluation_summary_content():
    """Verify the content exactly matches computation from trusted fixtures."""
    summary_path = '/home/user/evaluation_summary.txt'

    with tempfile.TemporaryDirectory() as td:
        artifacts_path = Path(td) / 'artifacts.csv'
        seed_path = Path(td) / 'random_seed'
        artifacts_path.write_bytes(ORIGINAL_ARTIFACTS)
        seed_path.write_bytes(ORIGINAL_SEED)

        cmd = (
            f"grep -E '^[^,]+,[0-9.]+,[0-9.]+,[0-9.]+$' '{artifacts_path}' | "
            f"shuf -n 30 --random-source='{seed_path}' | "
            "awk -F',' '{sum_acc+=$2; sum_loss+=$3} END "
            "{printf \"Mean Accuracy: %.4f, Mean Loss: %.4f\", sum_acc/NR, sum_loss/NR}'"
        )

        try:
            result = subprocess.run(
                cmd, shell=True, capture_output=True, text=True, check=True
            )
            expected_content = result.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Failed to compute expected truth data: {e.stderr}")

    with open(summary_path, 'r') as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"Content of {summary_path} is incorrect.\n"
        f"Expected: '{expected_content}'\n"
        f"Got: '{actual_content}'"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
