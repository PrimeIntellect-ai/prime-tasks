#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import subprocess

import cv2
import h5py
import numpy as np


def decode_expected_time_series():
    cap = cv2.VideoCapture('/app/reactor_vibration.mp4')
    assert cap.isOpened(), "Could not open /app/reactor_vibration.mp4."

    values = []
    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            assert frame.ndim == 3 and frame.shape[0] >= 100 and frame.shape[1] >= 100, \
                "Video frame is too small for the required 100x100 region."
            roi = frame[:100, :100]
            # OpenCV supplies BGR pixels; apply Rec. 601 to RGB components.
            b = roi[:, :, 0].astype(np.float64)
            g = roi[:, :, 1].astype(np.float64)
            r = roi[:, :, 2].astype(np.float64)
            gray = 0.299 * r + 0.587 * g + 0.114 * b
            values.append(np.mean(gray, dtype=np.float64))
    finally:
        cap.release()

    assert values, "No frames were decoded from the input video."
    return np.asarray(values, dtype=np.float64)


def test_hdf5_output_and_metric():
    project = '/home/user/vibration_analyzer'
    manifest = os.path.join(project, 'Cargo.toml')
    assert os.path.isfile(manifest), "Rust project is missing Cargo.toml."
    assert glob.glob(os.path.join(project, '**', '*.rs'), recursive=True), \
        "Rust project contains no Rust source files."

    # Derive the expected signal from the original video before executing the
    # submitted application.
    expected = decode_expected_time_series()

    output_path = '/home/user/analysis.h5'
    if os.path.exists(output_path):
        os.remove(output_path)

    try:
        result = subprocess.run(
            ['cargo', 'run', '--offline', '--manifest-path', manifest],
            cwd=project,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=600,
        )
    except subprocess.TimeoutExpired as e:
        raise AssertionError(f"Rust application timed out: {e}")

    assert result.returncode == 0, \
        f"Rust application failed with exit code {result.returncode}:\n{result.stdout[-4000:]}"
    assert os.path.isfile(output_path), f"Output file {output_path} was not created."

    try:
        with h5py.File(output_path, 'r') as f:
            assert 'dominant_frequency' in f, "Dataset 'dominant_frequency' missing in HDF5."
            assert 'time_series' in f, "Dataset 'time_series' missing in HDF5."

            freq_dataset = f['dominant_frequency']
            time_dataset = f['time_series']
            freq = float(freq_dataset[...])
            time_series = time_dataset[...]

            assert isinstance(time_series, np.ndarray), "'time_series' should be an array."
            assert time_series.ndim == 1, "'time_series' should be a 1D array."
            assert time_dataset.dtype.kind == 'f' and time_dataset.dtype.itemsize == 8, \
                "'time_series' should contain f64 values."
            assert freq_dataset.shape == (), "'dominant_frequency' should be a scalar dataset."
            assert freq_dataset.dtype.kind == 'f' and freq_dataset.dtype.itemsize == 8, \
                "'dominant_frequency' should be an f64 value."
            assert time_series.shape == expected.shape, \
                f"Expected one value for each of {expected.size} frames, got {time_series.size}."
            assert np.all(np.isfinite(time_series)), "'time_series' contains non-finite values."

            differences = np.abs(time_series - expected)
            assert np.allclose(time_series, expected, rtol=1e-7, atol=1e-4), \
                f"'time_series' does not match frame-derived Rec. 601 means; maximum error: {differences.max():.8f}."
    except Exception as e:
        raise AssertionError(f"Failed to read HDF5 file or missing datasets: {e}")

    truth = 5.34
    error = abs(freq - truth)
    assert error <= 0.05, f"Dominant frequency {freq:.4f} Hz is not within 0.05 Hz of truth {truth} Hz. Absolute error: {error:.4f}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
