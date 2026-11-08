#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import shutil
import stat
import subprocess
import tempfile

import numpy as np
import pandas as pd
import pytest

OUTPUT_PATH = "/app/output/scores.csv"
INPUT_PATH = "/app/data/input.csv"
SOURCE_PATH = "/app/src/engine.cpp"
BINARY_PATH = "/app/bin/engine"
ALPHA = 0.00845
THRESHOLD = 1e-5


def parse_val(v):
    if isinstance(v, str):
        v = v.replace('D', 'E').replace('d', 'e')
    return float(v)


def test_01_scores_csv_exists_and_mse_threshold():
    assert os.path.isfile(OUTPUT_PATH), f"Expected output file {OUTPUT_PATH} does not exist."
    assert os.path.isfile(INPUT_PATH), f"Input data file not found at {INPUT_PATH}"

    try:
        agent_df = pd.read_csv(OUTPUT_PATH)
    except Exception as e:
        pytest.fail(f"Failed to read {OUTPUT_PATH} as CSV: {e}")

    assert 'score' in agent_df.columns, f"Column 'score' not found in {OUTPUT_PATH}"

    try:
        raw_df = pd.read_csv(INPUT_PATH)
    except Exception as e:
        pytest.fail(f"Failed to read {INPUT_PATH} as CSV: {e}")

    truth_scores = []
    for _, row in raw_df.iterrows():
        x = parse_val(row['x'])
        y = parse_val(row['y'])
        truth_scores.append((x * y) / (x - y + ALPHA))

    agent_scores = agent_df['score'].values
    truth_scores = np.array(truth_scores)

    assert len(agent_scores) == len(truth_scores), (
        f"Length mismatch: Agent provided {len(agent_scores)} scores, "
        f"but expected {len(truth_scores)} scores based on input."
    )

    mse = np.mean((agent_scores - truth_scores) ** 2)
    assert mse <= THRESHOLD, (
        f"MSE too high! Measured MSE: {mse:.8f}, Threshold: {THRESHOLD}. "
        "Check if the legacy exponent format ('D') was correctly parsed and "
        "the correct alpha value (0.00845) was used."
    )


def read_and_check_output(expected):
    assert os.path.isfile(OUTPUT_PATH), "Engine did not create /app/output/scores.csv"
    with open(OUTPUT_PATH, newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['id', 'score'], (
            f"Expected exactly the columns id,score, got {reader.fieldnames}"
        )
        rows = list(reader)

    assert len(rows) == len(expected), (
        f"Engine emitted {len(rows)} rows for {len(expected)} input rows"
    )

    actual_scores = []
    expected_scores = []
    for row, (expected_id, x, y) in zip(rows, expected):
        assert row['id'] == str(expected_id), (
            f"Expected output id {expected_id}, got {row['id']}"
        )
        try:
            score = float(row['score'])
        except Exception as e:
            pytest.fail(f"Invalid score for id {expected_id}: {e}")
        assert math.isfinite(score), f"Non-finite score for id {expected_id}"
        actual_scores.append(score)
        expected_scores.append((x * y) / (x - y + ALPHA))

    mse = float(np.mean((np.array(actual_scores) - np.array(expected_scores)) ** 2))
    assert mse <= THRESHOLD, (
        f"Engine failed randomized legacy-exponent test: MSE {mse:.8f} exceeds {THRESHOLD}"
    )


def run_engine(executable, expected):
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        [executable], cwd="/app", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Engine {executable} exited with {result.returncode}. stderr: {result.stderr}"
    )
    read_and_check_output(expected)


def test_02_source_and_compiled_engine_process_unseen_legacy_data():
    assert os.path.isfile(SOURCE_PATH), f"Expected source file {SOURCE_PATH} does not exist"
    assert os.path.isfile(BINARY_PATH), f"Expected compiled engine {BINARY_PATH} does not exist"
    assert os.access(BINARY_PATH, os.X_OK), f"Compiled engine {BINARY_PATH} is not executable"
    with open(BINARY_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{BINARY_PATH} is not a compiled ELF executable"

    rng = random.SystemRandom()
    expected = []
    lines = ["id,x,y"]
    for i in range(9):
        row_id = rng.randrange(10000, 99999)
        y = rng.uniform(0.015, 0.15)
        x = y + rng.uniform(-0.0012, 0.0012)
        expected.append((row_id, x, y))
        x_token = format(x, '.12E')
        y_token = format(y, '.12E')
        if i % 2 == 0:
            x_token = x_token.replace('E', 'D')
        else:
            y_token = y_token.replace('E', 'D')
        lines.append(f"{row_id},{x_token},{y_token}")

    with tempfile.TemporaryDirectory() as td:
        input_backup = os.path.join(td, "input.csv")
        output_backup = os.path.join(td, "scores.csv")
        shutil.copy2(INPUT_PATH, input_backup)
        had_output = os.path.isfile(OUTPUT_PATH)
        if had_output:
            shutil.copy2(OUTPUT_PATH, output_backup)

        rebuilt = os.path.join(td, "engine_from_submitted_source")
        try:
            with open(INPUT_PATH, 'w') as f:
                f.write('\n'.join(lines) + '\n')

            compile_result = subprocess.run(
                ["g++", "-O3", SOURCE_PATH, "-o", rebuilt],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
            )
            assert compile_result.returncode == 0, (
                f"Submitted engine.cpp does not compile: {compile_result.stderr}"
            )

            run_engine(BINARY_PATH, expected)
            run_engine(rebuilt, expected)
        finally:
            shutil.copy2(input_backup, INPUT_PATH)
            if had_output:
                shutil.copy2(output_backup, OUTPUT_PATH)
            elif os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
