#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import secrets
import subprocess
from pathlib import Path

import pandas as pd
import numpy as np
import pytest

ORIGINAL_VALUES = np.array([45.0, 52.0, 48.0, 60.0, 55.0, 50.0, 62.0, 65.0, 70.0, 68.0])
ORIGINAL_ROLLING = np.array([45.0, 48.5, 48.33, 53.33, 54.33, 55.0, 55.67, 59.0, 65.67, 67.67])
EXPECTED_HEADERS = ['Index', 'Value', 'RollingAvg']


def read_results(csv_path):
    assert os.path.exists(csv_path), f"File {csv_path} does not exist."
    assert os.path.isfile(csv_path), f"Path {csv_path} is not a file."
    try:
        df = pd.read_csv(csv_path)
    except Exception as e:
        pytest.fail(f"Failed to read {csv_path} as CSV: {e}")
    assert list(df.columns) == EXPECTED_HEADERS, \
        f"CSV headers {list(df.columns)} do not match expected {EXPECTED_HEADERS}."
    return df


def numeric_column(df, name):
    try:
        values = pd.to_numeric(df[name], errors='raise').to_numpy(dtype=float)
    except (TypeError, ValueError):
        pytest.fail(f"{name} column contains non-numeric values.")
    assert np.all(np.isfinite(values)), f"{name} column contains non-finite values."
    return values


def rolling(values):
    return np.array([
        round(sum(values[max(0, i - 2):i + 1]) / len(values[max(0, i - 2):i + 1]), 2)
        for i in range(len(values))
    ], dtype=float)


def test_rolling_averages_csv():
    """Verify the submitted CSV, including indices, transcribed values, and rolling averages."""
    csv_path = '/home/user/rolling_averages.csv'
    df = read_results(csv_path)

    indices = numeric_column(df, 'Index')
    values = numeric_column(df, 'Value')
    assert len(df) == len(ORIGINAL_VALUES), \
        f"CSV has {len(df)} rows; expected {len(ORIGINAL_VALUES)}."
    assert np.array_equal(indices, np.arange(1, len(ORIGINAL_VALUES) + 1, dtype=float)), \
        f"Index must contain consecutive values starting at 1; got {indices.tolist()}."
    assert np.array_equal(values, ORIGINAL_VALUES), \
        f"Value column does not contain the dictated measurements; got {values.tolist()}."

    try:
        agent_vals = df['RollingAvg'].astype(float).values
    except ValueError:
        pytest.fail("RollingAvg column contains non-numeric values.")

    min_len = min(len(ORIGINAL_ROLLING), len(agent_vals))
    mse = np.mean((ORIGINAL_ROLLING[:min_len] - agent_vals[:min_len])**2) if min_len > 0 else 100.0
    if len(ORIGINAL_ROLLING) != len(agent_vals):
        mse += abs(len(ORIGINAL_ROLLING) - len(agent_vals)) * 10.0

    threshold = 2.0
    assert mse <= threshold, \
        f"MSE of RollingAvg is {mse:.4f}, which exceeds the threshold of {threshold}."


def test_process_metrics_script():
    """Verify that the processing script exists and is executable."""
    script_path = '/home/user/process_metrics.sh'
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Path {script_path} is not a file."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR) or bool(st.st_mode & stat.S_IXGRP) or bool(st.st_mode & stat.S_IXOTH), \
        f"Script {script_path} is not executable."


def test_process_metrics_script_executes_pipeline():
    """Run the script on a newly generated dictation and validate all produced columns."""
    script_path = '/home/user/process_metrics.sh'
    audio_path = Path('/app/metrics_dictation.wav')
    csv_path = Path('/home/user/rolling_averages.csv')

    original_audio = audio_path.read_bytes()
    original_csv = csv_path.read_bytes() if csv_path.exists() else None

    rng = secrets.SystemRandom()
    generated_values = rng.sample(range(21, 90), 10)
    assert generated_values != ORIGINAL_VALUES.astype(int).tolist()
    dictation = ' '.join(
        f"Measurement {i}: {value}." for i, value in enumerate(generated_values, start=1)
    )

    try:
        subprocess.run(
            ['espeak', '-w', str(audio_path), dictation],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        if csv_path.exists():
            csv_path.unlink()

        try:
            result = subprocess.run(
                [script_path],
                cwd='/home/user',
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=180,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("process_metrics.sh did not finish within 180 seconds.")

        assert result.returncode == 0, \
            f"process_metrics.sh exited with {result.returncode}. stdout: {result.stdout} stderr: {result.stderr}"
        assert csv_path.exists(), "process_metrics.sh did not create /home/user/rolling_averages.csv."

        df = read_results(str(csv_path))
        assert len(df) == len(generated_values), \
            f"Generated CSV has {len(df)} rows; expected {len(generated_values)}."

        indices = numeric_column(df, 'Index')
        values = numeric_column(df, 'Value')
        averages = numeric_column(df, 'RollingAvg')
        expected_values = np.array(generated_values, dtype=float)
        expected_rolling = rolling(generated_values)

        assert np.array_equal(indices, np.arange(1, len(generated_values) + 1, dtype=float)), \
            f"Index must contain consecutive values starting at 1; got {indices.tolist()}."
        assert np.array_equal(values, expected_values), \
            f"Script did not transcribe the generated measurements; got {values.tolist()}."

        mse = np.mean((expected_rolling - averages) ** 2)
        assert mse <= 2.0, \
            f"Generated-input RollingAvg MSE is {mse:.4f}, which exceeds the threshold of 2.0."
        assert np.allclose(averages, expected_rolling, atol=0.005, rtol=0), \
            f"Generated-input rolling averages are not rounded correctly; expected {expected_rolling.tolist()}, got {averages.tolist()}."
    finally:
        audio_path.parent.mkdir(parents=True, exist_ok=True)
        audio_path.write_bytes(original_audio)
        if original_csv is None:
            if csv_path.exists():
                csv_path.unlink()
        else:
            csv_path.parent.mkdir(parents=True, exist_ok=True)
            csv_path.write_bytes(original_csv)


def test_cron_schedule_file():
    """Verify that the cron file exists and contains the correct schedule."""
    cron_path = '/home/user/metrics_pipeline.cron'
    assert os.path.exists(cron_path), f"Cron file {cron_path} does not exist."
    assert os.path.isfile(cron_path), f"Path {cron_path} is not a file."

    with open(cron_path, 'r') as f:
        content = f.read().strip()

    assert '/home/user/process_metrics.sh' in content, \
        "Cron file does not reference /home/user/process_metrics.sh"
    valid_cron_start = re.search(r'^(\*/15|0,15,30,45)\s+\*\s+\*\s+\*\s+\*', content, re.MULTILINE)
    assert valid_cron_start is not None, \
        f"Cron file does not contain a valid 15-minute schedule (e.g. '*/15 * * * *'). Content: {content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
