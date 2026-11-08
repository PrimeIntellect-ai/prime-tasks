#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import struct
import wave

import pytest
import requests


def compute_expected_rms(file_path, window_ms):
    with wave.open(file_path, 'rb') as wf:
        nchannels = wf.getnchannels()
        sampwidth = wf.getsampwidth()
        framerate = wf.getframerate()
        nframes = wf.getnframes()

        assert nchannels == 1, "Expected mono audio"
        assert sampwidth == 2, "Expected 16-bit PCM"

        raw_data = wf.readframes(nframes)

    samples = struct.unpack(f"<{nframes}h", raw_data)
    samples_normalized = [s / 32768.0 for s in samples]
    samples_per_window = int(framerate * window_ms / 1000)

    rms_values = []
    for i in range(0, len(samples_normalized) - samples_per_window + 1, samples_per_window):
        window = samples_normalized[i:i + samples_per_window]
        rms = math.sqrt(sum(x * x for x in window) / samples_per_window)
        rms_values.append(rms)

    return rms_values


def post_json(path, payload):
    url = f"http://127.0.0.1:8080{path}"
    try:
        response = requests.post(url, json=payload, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to server at {url}: {exc}")

    assert response.status_code == 200, (
        f"Expected status 200, got {response.status_code}. Body: {response.text}"
    )
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")


def assert_rms_response(window_ms):
    expected_rms = compute_expected_rms("/app/dataset_sample.wav", window_ms)
    actual_rms = post_json("/features/rms", {"window_ms": window_ms})

    assert isinstance(actual_rms, list), "Expected a JSON array of floats"
    assert len(actual_rms) == len(expected_rms), (
        f"Expected {len(expected_rms)} windows, got {len(actual_rms)}"
    )
    for i, (actual, expected) in enumerate(zip(actual_rms, expected_rms)):
        assert isinstance(actual, (int, float)) and not isinstance(actual, bool), (
            f"RMS value at window {i} is not numeric"
        )
        assert math.isfinite(actual), f"RMS value at window {i} is not finite"
        assert math.isclose(actual, expected, abs_tol=1e-4), (
            f"RMS mismatch at window {i}: expected {expected}, got {actual}"
        )


def assert_threshold_response(window_ms, threshold):
    expected_rms = compute_expected_rms("/app/dataset_sample.wav", window_ms)
    expected_active = sum(1 for rms in expected_rms if rms > threshold)
    data = post_json(
        "/tune/threshold",
        {"window_ms": window_ms, "threshold": threshold},
    )

    assert isinstance(data, dict), "Expected a JSON object"
    assert "active_windows" in data, "Key 'active_windows' missing in response"
    actual_active = data["active_windows"]
    assert actual_active == expected_active, (
        f"Expected {expected_active} active windows, got {actual_active}"
    )


def test_rms_endpoint():
    file_path = "/app/dataset_sample.wav"
    assert os.path.exists(file_path), "Audio file is missing"
    assert_rms_response(100)


def test_tune_threshold_endpoint():
    file_path = "/app/dataset_sample.wav"
    assert os.path.exists(file_path), "Audio file is missing"
    assert_threshold_response(100, 0.05)


def test_multiple_unpredictable_window_sizes_and_thresholds():
    file_path = "/app/dataset_sample.wav"
    assert os.path.exists(file_path), "Audio file is missing"

    # Select after the agent has finished, so a fixed response table cannot know
    # which window sizes will be exercised. Multiples of 25 ms are excluded
    # because this sample's squared waveform is periodic over those windows.
    candidates = [w for w in range(11, 241) if w != 100 and w % 25 != 0]
    window_sizes = secrets.SystemRandom().sample(candidates, 5)

    for window_ms in window_sizes:
        assert_rms_response(window_ms)
        expected_rms = compute_expected_rms(file_path, window_ms)
        assert expected_rms

        low = 0.0
        high = max(expected_rms) + 0.01
        middle = (min(expected_rms) + max(expected_rms)) / 2.0
        for threshold in (low, middle, high):
            assert_threshold_response(window_ms, threshold)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
