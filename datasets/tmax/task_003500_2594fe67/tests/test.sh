#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
import time

import numpy as np
import pandas as pd

HOME = '/home/user'
FRAME_STATS = f'{HOME}/frame_stats.csv'
SOURCE = f'{HOME}/pipeline.cpp'
BINARY = f'{HOME}/pipeline'
PREDICTIONS = f'{HOME}/predictions.csv'


def run_pipeline(timeout=10):
    start = time.perf_counter()
    proc = subprocess.run(
        [BINARY], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=timeout
    )
    elapsed = time.perf_counter() - start
    assert proc.returncode == 0, (
        f'pipeline exited with {proc.returncode}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
    )
    assert os.path.exists(PREDICTIONS), 'The pipeline did not generate predictions.csv.'
    return elapsed


def read_predictions():
    try:
        df = pd.read_csv(PREDICTIONS)
    except Exception as exc:
        raise AssertionError(f'Failed to read {PREDICTIONS}: {exc}')

    required = {'frame_index', 'actual_target', 'predicted_target'}
    assert required.issubset(df.columns), (
        f'Missing columns in predictions.csv. Expected {required}, found {set(df.columns)}'
    )
    assert len(df) > 0, 'predictions.csv must contain validation predictions.'
    for col in required:
        values = pd.to_numeric(df[col], errors='coerce').to_numpy(dtype=float)
        assert np.isfinite(values).all(), f'{col} contains non-numeric or non-finite values.'
    return df


def test_original_artifacts_and_generated_predictions():
    # Keep the original artifact assertions.
    assert os.path.exists(FRAME_STATS), 'The frame_stats.csv file is missing.'
    assert os.path.exists(SOURCE), 'The pipeline.cpp source file is missing.'
    assert os.path.exists(BINARY), 'The compiled pipeline executable is missing.'
    assert os.access(BINARY, os.X_OK), 'The pipeline file is not executable.'
    with open(BINARY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'pipeline must be a compiled executable.'

    # Check that frame_stats has the shape of frame-level data from this video,
    # rather than a fabricated one-row input.
    stats = pd.read_csv(FRAME_STATS)
    assert {'frame_index', 'diff_score'}.issubset(stats.columns), (
        'frame_stats.csv must contain frame_index and diff_score columns.'
    )
    probe = subprocess.run(
        ['ffprobe', '-v', 'error', '-count_frames', '-select_streams', 'v:0',
         '-show_entries', 'stream=nb_read_frames', '-of', 'default=nw=1:nk=1',
         '/app/traffic_camera.mp4'],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    frame_count = int(probe.stdout.strip())
    assert len(stats) in (frame_count, frame_count - 1), (
        f'Expected one statistic per frame (or per consecutive-frame pair); '
        f'video has {frame_count} frames but CSV has {len(stats)} rows.'
    )
    indices = pd.to_numeric(stats['frame_index'], errors='coerce').to_numpy(dtype=float)
    assert np.isfinite(indices).all() and np.all(indices == np.floor(indices)), (
        'frame_index values must be finite integers.'
    )
    assert np.all(np.diff(indices) == 1), 'frame_index values must be consecutive and ordered.'
    scores = pd.to_numeric(stats['diff_score'], errors='coerce').to_numpy(dtype=float)
    finite = scores[np.isfinite(scores)]
    assert len(finite) >= int(0.9 * len(scores)), 'Too many diff_score values are missing.'
    assert np.all(finite >= 0), 'Difference scores must be non-negative.'
    assert np.any(finite > 0), 'Difference scores cannot all be zero for the supplied video.'

    # The submitted source must include an actual timing facility for its own benchmark.
    source_text = open(SOURCE, encoding='utf-8', errors='replace').read()
    timing_api = re.search(
        r'chrono|steady_clock|high_resolution_clock|clock_gettime|std::clock|\bclock\s*\(',
        source_text
    )
    assert timing_api, 'pipeline.cpp does not track inference time with a timing API.'

    # Compile the submitted source ourselves, then execute it on the submitted frame data.
    compile_proc = subprocess.run(
        ['g++', '-O3', SOURCE, '-o', BINARY],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert compile_proc.returncode == 0, f'Compilation failed:\n{compile_proc.stderr}'
    run_pipeline()

    # Keep the original predictions existence, schema, and MSE assertions.
    assert os.path.exists(PREDICTIONS), 'The predictions.csv file is missing.'
    pred = read_predictions()
    actual = pd.to_numeric(pred['actual_target']).to_numpy(dtype=float)
    predicted = pd.to_numeric(pred['predicted_target']).to_numpy(dtype=float)
    mse = np.mean((actual - predicted) ** 2)
    assert mse <= 0.05, f'FAIL: MSE {mse:.4f} > 0.05'


def test_pipeline_behavior_nan_rolling_regression_split_and_speed():
    # Replace only the input with a verifier-derived fixture. Valid scores form a
    # linear sequence, while NaN rows ensure that converting missing values to zero
    # changes rolling windows, targets, and regression results.
    rows = []
    valid_indices = []
    valid_scores = []
    missing = {7, 18, 31, 46}
    valid_number = 0
    for frame_index in range(60):
        if frame_index in missing:
            rows.append((frame_index, 'NaN'))
        else:
            score = 2.0 + 0.01 * valid_number
            rows.append((frame_index, f'{score:.8f}'))
            valid_indices.append(frame_index)
            valid_scores.append(score)
            valid_number += 1

    with open(FRAME_STATS, 'w', encoding='utf-8') as f:
        f.write('frame_index,diff_score\n')
        for index, score in rows:
            f.write(f'{index},{score}\n')

    # Independently derive rolling features, N+5 targets, the chronological 70/30
    # split, and the least-squares model required by the instruction.
    rolling = np.convolve(np.asarray(valid_scores, dtype=float), np.ones(5) / 5.0, mode='valid')
    rolling_end_indices = np.asarray(valid_indices[4:], dtype=int)
    x = rolling[:-5]
    y = rolling[5:]
    input_frame_indices = rolling_end_indices[:-5]
    target_frame_indices = rolling_end_indices[5:]
    split = int(math.floor(0.70 * len(x)))
    assert split >= 2 and split < len(x)

    x_train, y_train = x[:split], y[:split]
    x_mean, y_mean = x_train.mean(), y_train.mean()
    slope = np.sum((x_train - x_mean) * (y_train - y_mean)) / np.sum((x_train - x_mean) ** 2)
    intercept = y_mean - slope * x_mean
    expected_actual = y[split:]
    expected_predicted = intercept + slope * x[split:]

    # Run multiple times and use the best end-to-end runtime. End-to-end execution
    # is stricter than the required inference-only 50 ms limit while reducing noise.
    elapsed = []
    for _ in range(3):
        elapsed.append(run_pipeline(timeout=2))
    assert min(elapsed) < 0.050, (
        f'Pipeline execution never completed within 50 ms; best was {min(elapsed)*1000:.2f} ms.'
    )

    pred = read_predictions()
    assert len(pred) == len(expected_actual), (
        f'Expected {len(expected_actual)} validation rows after a 70/30 split, got {len(pred)}.'
    )
    actual = pd.to_numeric(pred['actual_target']).to_numpy(dtype=float)
    predicted = pd.to_numeric(pred['predicted_target']).to_numpy(dtype=float)
    reported_indices = pd.to_numeric(pred['frame_index']).to_numpy(dtype=float)

    assert np.allclose(actual, expected_actual, rtol=1e-6, atol=1e-5), (
        'actual_target was not independently derived from cleaned five-frame rolling averages.'
    )
    assert np.allclose(predicted, expected_predicted, rtol=1e-5, atol=1e-4), (
        'predicted_target does not match linear regression trained on the first 70% of samples.'
    )
    # Accept either the input window's frame index or the future target window's
    # frame index, since the instruction does not specify which one labels a pair.
    valid_input_labels = input_frame_indices[split:].astype(float)
    valid_target_labels = target_frame_indices[split:].astype(float)
    assert (np.array_equal(reported_indices, valid_input_labels) or
            np.array_equal(reported_indices, valid_target_labels)), (
        'frame_index values do not correspond to the validation prediction pairs.'
    )
    independent_mse = np.mean((expected_actual - predicted) ** 2)
    assert independent_mse <= 0.05, f'Independent MSE {independent_mse:.6f} exceeds 0.05.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
