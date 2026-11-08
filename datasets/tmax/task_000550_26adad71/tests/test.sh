#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import shutil
import subprocess
import tempfile

import cv2
import numpy as np
import pytest

SCRIPT_PATH = "/home/user/run_analysis.sh"
OUTPUT_PATH = "/home/user/output.json"
VIDEO_PATH = "/app/blinking.mp4"


def video_metrics(path):
    cap = cv2.VideoCapture(path)
    assert cap.isOpened(), f"Could not open video {path}."
    fps = float(cap.get(cv2.CAP_PROP_FPS))
    values = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if frame.ndim == 3:
            frame = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        values.append(float(np.mean(frame)))
    cap.release()

    assert fps > 0 and len(values) > 1, "Video did not contain a usable signal."
    signal = np.asarray(values, dtype=float)
    spectrum = np.abs(np.fft.rfft(signal - np.mean(signal)))
    spectrum[0] = 0.0
    frequencies = np.fft.rfftfreq(len(signal), d=1.0 / fps)
    frequency = float(frequencies[int(np.argmax(spectrum))])
    integral = float(np.trapz(signal, dx=1.0 / fps))
    return frequency, integral


def run_script():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        ["/bin/bash", SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=240,
    )
    assert result.returncode == 0, (
        f"Analysis script exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."

    with open(OUTPUT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{OUTPUT_PATH} is not a valid JSON file.")


def require_metrics(data):
    assert "frequency" in data, "Missing 'frequency' in output JSON."
    assert "integral" in data, "Missing 'integral' in output JSON."
    assert "frequency_std" in data, "Missing 'frequency_std' in output JSON."
    try:
        freq = float(data["frequency"])
        integral = float(data["integral"])
        std = float(data["frequency_std"])
    except (TypeError, ValueError):
        pytest.fail("Values in JSON must be convertible to floats.")
    assert all(math.isfinite(x) for x in (freq, integral, std)), "Metric values must be finite."
    return freq, integral, std


def assert_integral_close(actual, expected):
    tolerance = max(2.0, 0.02 * abs(expected))
    assert abs(actual - expected) <= tolerance, (
        f"Integral differs from the decoded-video trapezoidal integral: "
        f"got {actual}, expected {expected}, tolerance {tolerance}."
    )


def make_challenge_video(path):
    fps = 30
    frames = 300
    width = height = 200
    frequency = random.choice([1.3, 1.7, 3.2, 4.1])
    baseline = random.choice([72.0, 96.0, 154.0, 181.0])
    phase = random.uniform(0.2, 5.8)
    writer = cv2.VideoWriter(
        path, cv2.VideoWriter_fourcc(*"mp4v"), fps, (width, height), isColor=False
    )
    assert writer.isOpened(), "Could not create verifier challenge video."
    for i in range(frames):
        value = baseline + 42.0 * np.sin(2.0 * np.pi * frequency * i / fps + phase)
        frame = np.full((height, width), np.clip(value, 0, 255), dtype=np.uint8)
        writer.write(frame)
    writer.release()


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Bash script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a regular file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Bash script {SCRIPT_PATH} is not executable."


def test_output_json_metrics():
    fd, backup_path = tempfile.mkstemp(suffix=".mp4")
    os.close(fd)
    shutil.copy2(VIDEO_PATH, backup_path)
    try:
        make_challenge_video(VIDEO_PATH)
        expected_freq, expected_integral = video_metrics(VIDEO_PATH)
        challenge_data = run_script()
        challenge_freq, challenge_integral, _ = require_metrics(challenge_data)
        challenge_error = abs(challenge_freq - expected_freq) / expected_freq
        assert challenge_error <= 0.1, (
            f"Frequency error {challenge_error:.4f} exceeds threshold of 0.1 on the "
            f"verification video. Extracted freq: {challenge_freq}, Expected: {expected_freq}"
        )
        assert_integral_close(challenge_integral, expected_integral)
    finally:
        shutil.copy2(backup_path, VIDEO_PATH)
        os.remove(backup_path)

    expected_video_freq, expected_integral = video_metrics(VIDEO_PATH)
    data = run_script()
    freq, integral, std = require_metrics(data)

    expected_freq = 2.5
    freq_error = abs(freq - expected_freq) / expected_freq
    assert freq_error <= 0.1, (
        f"Frequency error {freq_error:.4f} exceeds threshold of 0.1. "
        f"Extracted freq: {freq}, Expected: {expected_freq}"
    )
    decoded_error = abs(freq - expected_video_freq) / expected_video_freq
    assert decoded_error <= 0.1, (
        f"Frequency does not match the decoded video: got {freq}, expected {expected_video_freq}."
    )
    assert_integral_close(integral, expected_integral)
    assert std > 0, f"Frequency standard deviation must be > 0, got {std}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
