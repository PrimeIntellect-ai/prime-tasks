#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import subprocess
import tempfile
import time

import cv2
import numpy as np
import pandas as pd
import pytest


def compute_ground_truth(video_path):
    cap = cv2.VideoCapture(video_path)
    results = []
    frame_id = 1
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        img = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        img = img.astype(float) / 255.0

        A = img[:100, :100]
        y = img[:100, 100:200].mean(axis=1)

        # Stable SVD pseudo-inverse
        if np.all(A == 0):
            x = np.zeros(A.shape[1])
        else:
            x = np.linalg.pinv(A.T @ A) @ A.T @ y

        results.append({
            'FrameID': frame_id,
            'PeakWavelength': int(np.argmax(x)),
            'MaxIntensity': float(np.max(x))
        })
        frame_id += 1
    cap.release()
    return pd.DataFrame(results)


def run_deconvolve(image, frame_id):
    with tempfile.TemporaryDirectory() as tmpdir:
        frame_path = os.path.join(tmpdir, f"frame_{frame_id:04d}.png")
        assert cv2.imwrite(frame_path, image), "Failed to create numerical-stability test frame"
        result = subprocess.run(
            ["python3", "/home/user/deconvolve.py", frame_path],
            capture_output=True,
            text=True,
            timeout=15,
        )

    assert result.returncode == 0, (
        f"deconvolve.py failed on a degenerate frame.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    lines = [line for line in result.stdout.splitlines() if line.strip()]
    assert len(lines) == 1, f"Expected one CSV result from deconvolve.py, got: {result.stdout!r}"
    row = next(csv.reader([lines[0]]))
    assert len(row) == 3, f"Malformed deconvolve.py output: {lines[0]!r}"

    parsed_id = int(row[0])
    peak = float(row[1])
    max_intensity = float(row[2])
    assert parsed_id == frame_id, f"deconvolve.py returned FrameID {parsed_id}, expected {frame_id}"
    assert math.isfinite(peak) and peak.is_integer(), "PeakWavelength must be a finite integer"
    assert math.isfinite(max_intensity), "MaxIntensity must be finite"
    return int(peak), max_intensity


def test_deconvolve_is_numerically_stable():
    script_path = "/home/user/deconvolve.py"
    assert os.path.isfile(script_path), f"Missing deconvolution implementation: {script_path}"

    # The original direct inverse crashes on this singular input. A stabilized
    # implementation must produce the zero-signal summary instead.
    blank = np.zeros((240, 320), dtype=np.uint8)
    peak, max_intensity = run_deconvolve(blank, 9001)
    assert peak == 0, f"Blank frame should have PeakWavelength 0, got {peak}"
    assert abs(max_intensity) <= 1e-12, (
        f"Blank frame should produce zero intensity, got {max_intensity}"
    )

    # A saturated frame is also rank deficient and must not crash or emit NaN/Inf.
    saturated = np.full((240, 320), 255, dtype=np.uint8)
    run_deconvolve(saturated, 9002)


def test_optimized_pipeline_performance_and_correctness():
    script_path = "/home/user/run_optimized.sh"
    assert os.path.exists(script_path), f"Missing optimized script: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"

    video_path = "/app/spectrometer_feed.mp4"
    assert os.path.exists(video_path), f"Missing video file: {video_path}"

    output_csv = "/home/user/final_spectra.csv"
    if os.path.exists(output_csv):
        os.remove(output_csv)

    start_time = time.time()
    result = subprocess.run([script_path], capture_output=True, text=True)
    elapsed_time = time.time() - start_time

    assert result.returncode == 0, f"Optimized script failed with return code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    assert os.path.exists(output_csv), f"Output CSV not found at {output_csv}"

    # Performance check
    baseline_time = 45.0
    speedup = baseline_time / elapsed_time
    assert speedup >= 3.0, f"Performance failed: Speedup is {speedup:.2f}x (Threshold >= 3.0x). Elapsed time: {elapsed_time:.2f}s"

    # Correctness check
    df_pred = pd.read_csv(output_csv)
    required_columns = ['FrameID', 'PeakWavelength', 'MaxIntensity']
    assert list(df_pred.columns) == required_columns, (
        f"CSV columns must be exactly {required_columns}, got {list(df_pred.columns)}"
    )

    for column in required_columns:
        df_pred[column] = pd.to_numeric(df_pred[column], errors='raise')
    assert np.isfinite(df_pred[required_columns].to_numpy(dtype=float)).all(), (
        "Output CSV contains NaN or infinite values"
    )

    df_pred = df_pred.sort_values('FrameID').reset_index(drop=True)
    df_true = compute_ground_truth(video_path).sort_values('FrameID').reset_index(drop=True)

    assert len(df_pred) == len(df_true), f"Frame count mismatch: expected {len(df_true)}, got {len(df_pred)}"

    assert np.array_equal(
        df_pred['FrameID'].to_numpy(), df_true['FrameID'].to_numpy()
    ), "FrameID values do not match the complete video frame sequence"

    assert np.array_equal(
        df_pred['PeakWavelength'].to_numpy(), df_true['PeakWavelength'].to_numpy()
    ), "PeakWavelength values do not match the stable reference computation"

    mse = ((df_pred['MaxIntensity'] - df_true['MaxIntensity'])**2).mean()
    assert mse < 0.001, f"Correctness failed: MSE is {mse:.6f} (Threshold < 0.001)"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
