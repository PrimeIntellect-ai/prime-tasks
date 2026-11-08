#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import wave
import numpy as np


def calculate_truth():
    wav_file = '/app/telemetry.wav'
    assert os.path.exists(wav_file), f"Input WAV file {wav_file} is missing."

    with wave.open(wav_file, 'rb') as w:
        assert w.getnchannels() == 1, "Expected mono audio."
        assert w.getsampwidth() == 2, "Expected 16-bit PCM audio."
        frames = w.readframes(w.getnframes())

    signal = np.frombuffer(frames, dtype='<i2').astype(np.float64)
    train_size = int(len(signal) * 0.7)
    train_signal = signal[:train_size]
    test_signal = signal[train_size:]
    train_mean = np.mean(train_signal)
    train_std = np.std(train_signal, ddof=0)
    return (test_signal - train_mean) / train_std


def test_test_features_mse():
    agent_file = '/home/user/test_features.bin'
    assert os.path.exists(agent_file), f"Agent output file {agent_file} is missing."

    agent_data = np.fromfile(agent_file, dtype=np.float64)
    truth_data = calculate_truth()

    assert len(agent_data) == len(truth_data), (
        f"Length mismatch: agent produced {len(agent_data)} samples, "
        f"expected {len(truth_data)} samples."
    )

    mse = np.mean((agent_data - truth_data)**2)
    assert mse <= 1e-5, f"MSE {mse} is greater than the threshold 1e-5."


def test_test_stats_file():
    stats_file = '/home/user/test_stats.txt'
    assert os.path.exists(stats_file), f"Stats file {stats_file} is missing."

    truth_data = calculate_truth()
    expected_mean = np.mean(truth_data)
    expected_std = np.std(truth_data, ddof=1)
    n = len(truth_data)
    margin = 1.96 * expected_std / np.sqrt(n)
    expected_lower = expected_mean - margin
    expected_upper = expected_mean + margin

    with open(stats_file, 'r') as f:
        content = f.read().strip()

    parts = content.split(',')
    assert len(parts) == 3, f"Expected 3 comma-separated values in {stats_file}, got {len(parts)}."

    try:
        agent_mean = float(parts[0])
        agent_lower = float(parts[1])
        agent_upper = float(parts[2])
    except ValueError:
        assert False, f"Could not parse floats from {stats_file}: {content}"

    # Allow a small tolerance for the stats due to potential ddof=0 vs ddof=1.
    assert abs(agent_mean - expected_mean) < 1e-2, f"Expected mean ~{expected_mean}, got {agent_mean}"
    assert abs(agent_lower - expected_lower) < 1e-2, f"Expected lower bound ~{expected_lower}, got {agent_lower}"
    assert abs(agent_upper - expected_upper) < 1e-2, f"Expected upper bound ~{expected_upper}, got {agent_upper}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
