#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import stat
import subprocess

import numpy as np
import pandas as pd
import pytest


def run_interpolation(command):
    sample = "100,10\n220,34\n"
    result = subprocess.run(
        command,
        input=sample,
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr

    rows = []
    for line in result.stdout.strip().splitlines():
        fields = line.split(',')
        assert len(fields) == 2, f"Malformed interpolation output: {line!r}"
        rows.append((int(fields[0]), float(fields[1])))

    assert len(rows) == 3, f"Expected three interpolation rows, got: {rows}"
    expected = [(100, 10.0), (160, 22.0), (220, 34.0)]
    for actual, wanted in zip(rows, expected):
        assert actual[0] == wanted[0]
        assert math.isclose(actual[1], wanted[1], rel_tol=0, abs_tol=1e-8), (
            f"Incorrect interpolation: expected {wanted}, got {actual}"
        )


def test_toolkit_fixed_and_functional():
    toolkit_dir = "/app/awk-ts-tools-1.0"
    awk_script = os.path.join(toolkit_dir, "interpolate.awk")
    makefile = os.path.join(toolkit_dir, "Makefile")

    assert os.path.isfile(awk_script), f"Missing interpolate.awk at {awk_script}"
    assert not os.path.islink(awk_script), "interpolate.awk must be a regular submitted file"
    assert os.access(awk_script, os.X_OK), "interpolate.awk is not executable"
    with open(awk_script, "r") as f:
        awk_content = f.read()
    assert "slope = (y2 + y1)" not in awk_content, (
        "The mathematical bug in interpolate.awk was not fixed."
    )

    assert os.path.isfile(makefile), f"Missing Makefile at {makefile}"
    assert not os.path.islink(makefile), "Makefile must be a regular submitted file"
    with open(makefile, "r") as f:
        makefile_content = f.read()
    assert "nonexistent-awk" not in makefile_content, (
        "The AWK_BIN environment variable still points to a nonexistent awk."
    )

    # Exercise both the repaired interpolation artifact and the Makefile entry point.
    run_interpolation(["awk", "-f", awk_script])
    run_interpolation(["make", "-s", "-C", toolkit_dir, "run"])


def test_pipeline_script_exists_and_runs():
    pipeline_script = "/home/user/pipeline.sh"
    assert os.path.isfile(pipeline_script), f"Pipeline script missing at {pipeline_script}"
    assert not os.path.islink(pipeline_script), "pipeline.sh must be a regular file"
    mode = os.stat(pipeline_script).st_mode
    assert stat.S_ISREG(mode), "pipeline.sh is not a regular file"
    assert os.access(pipeline_script, os.X_OK), f"Pipeline script {pipeline_script} is not executable."

    output = "/home/user/data/processed/master.csv"
    if os.path.lexists(output):
        os.remove(output)

    result = subprocess.run(
        ["runuser", "-u", "user", "--", pipeline_script],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"pipeline.sh failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(output), f"Processed master.csv missing at {output}"
    assert not os.path.islink(output), "master.csv must be a regular output file"


def test_cron_job_configured():
    result = subprocess.run(
        ['crontab', '-l', '-u', 'user'], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, "Failed to read crontab for user 'user'"
    crontab_content = result.stdout.strip()
    cron_pattern = re.compile(
        r'(?m)^(\*/15|0,15,30,45)\s+\*\s+\*\s+\*\s+\*.*(?:bash\s+)?/home/user/pipeline\.sh'
    )
    assert cron_pattern.search(crontab_content) is not None, (
        f"Cron job for pipeline.sh every 15 minutes not found in crontab:\n{crontab_content}"
    )


def test_processed_data_is_complete_and_accurate():
    predicted_path = "/home/user/data/processed/master.csv"
    assert os.path.isfile(predicted_path), f"Processed master.csv missing at {predicted_path}"

    try:
        pred_df = pd.read_csv(predicted_path, header=None)
        assert pred_df.shape[1] == 2, "master.csv must contain exactly two columns"
        pred_df.columns = ['timestamp', 'temperature']
        pred_df['timestamp'] = pd.to_numeric(pred_df['timestamp'], errors='raise')
        pred_df['temperature'] = pd.to_numeric(pred_df['temperature'], errors='raise')
    except Exception as exc:
        pytest.fail(f"Failed to parse master.csv: {exc}")

    expected_timestamps = np.arange(1600000000, 1600000000 + 3600 + 1, 60, dtype=np.int64)
    actual_timestamps = pred_df['timestamp'].to_numpy()

    assert len(pred_df) == len(expected_timestamps), (
        f"Expected the complete {len(expected_timestamps)}-row series, got {len(pred_df)} rows"
    )
    assert np.all(np.isfinite(pred_df['temperature'].to_numpy(dtype=float))), (
        "master.csv contains non-finite temperatures"
    )
    assert np.array_equal(actual_timestamps, expected_timestamps), (
        "master.csv must contain every exact 60-second timestamp once, sorted from the earliest "
        "raw timestamp through the latest"
    )

    truth = np.array([
        math.sin((int(t) - 1600000000) / 3600.0 * 2 * math.pi) * 10 + 20
        for t in expected_timestamps
    ])
    predicted = pred_df['temperature'].to_numpy(dtype=float)
    mse = np.mean((truth - predicted) ** 2)

    threshold = 0.05
    assert mse <= threshold, (
        f"MSE of interpolated temperatures is {mse:.4f}, which exceeds the threshold of {threshold}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
