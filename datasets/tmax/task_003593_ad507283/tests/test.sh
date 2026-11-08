#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import sys

import numpy as np
from scipy.io import wavfile
from scipy.optimize import curve_fit


def generate_truth():
    fs, source = wavfile.read('/app/pulse.wav')
    S = source.astype(np.float64) / np.max(np.abs(source))
    dt = 1.0 / fs
    c = 343.0
    gamma = 15.0
    L = 10.0

    dx = c * dt / 0.9
    Nx = int(np.ceil(L / dx)) + 1
    dx = L / (Nx - 1)
    Nt = len(S)

    u = np.zeros(Nx)
    u_prev = np.zeros(Nx)
    u_next = np.zeros(Nx)

    rec_idx = int(round(5.0 / dx))
    sample_x = np.array([1.0, 2.0, 3.0, 4.0, 5.0])
    sample_idx = [int(round(x / dx)) for x in sample_x]
    received_truth = np.zeros(Nt)
    peak_amplitudes = np.zeros(len(sample_x))

    C2 = (c * dt / dx) ** 2
    term1 = 2.0 / (1.0 + gamma * dt / 2.0)
    term2 = (1.0 - gamma * dt / 2.0) / (1.0 + gamma * dt / 2.0)

    for n in range(Nt):
        u_next[1:-1] = term1 * (
            u[1:-1] + C2 / 2.0 * (u[2:] - 2 * u[1:-1] + u[:-2])
        ) - term2 * u_prev[1:-1]
        u_next[0] = S[n]
        u_next[-1] = 0.0

        received_truth[n] = u_next[rec_idx]
        peak_amplitudes = np.maximum(peak_amplitudes, np.abs(u_next[sample_idx]))

        u_prev[:] = u[:]
        u[:] = u_next[:]

    received_truth = received_truth / np.max(np.abs(received_truth))
    truth_audio = (received_truth * 32767).astype(np.int16).astype(np.float32)

    def decay(x, A0, alpha):
        return A0 * np.exp(-alpha * x)

    (_, alpha_truth), _ = curve_fit(
        decay, sample_x, peak_amplitudes,
        p0=(peak_amplitudes[0], 15.0 / (2.0 * 343.0)),
        bounds=([0.0, 0.0], [np.inf, np.inf]),
        maxfev=10000,
    )
    return fs, truth_audio, float(alpha_truth)


def test_received_signal_mse_and_format():
    agent_file = '/home/user/received_signal.wav'
    assert os.path.isfile(agent_file), f"Agent output {agent_file} not found."

    try:
        fs_agent, agent_audio = wavfile.read(agent_file)
    except Exception as e:
        raise AssertionError(f"Error reading agent audio {agent_file}: {e}")

    fs_truth, truth_audio, _ = generate_truth()

    assert fs_agent == fs_truth, (
        f"Sample rate mismatch: agent has {fs_agent}, expected {fs_truth}"
    )
    assert agent_audio.dtype == np.int16, (
        f"Output must be 16-bit PCM, but decoded dtype is {agent_audio.dtype}"
    )
    assert agent_audio.ndim == 1, "Output WAV must be mono."
    assert len(agent_audio) == len(truth_audio) == 4000, (
        f"Output must contain exactly 4000 samples; got {len(agent_audio)}"
    )

    agent_audio = agent_audio.astype(np.float32)
    mse = np.mean(
        (agent_audio / 32767.0 - truth_audio / 32767.0) ** 2
    )
    assert mse <= 1e-4, f"MSE {mse} exceeds threshold 1e-4"


def test_attenuation_file():
    attenuation_file = '/home/user/attenuation.txt'
    assert os.path.isfile(attenuation_file), (
        f"Agent output {attenuation_file} not found."
    )
    with open(attenuation_file, 'r', encoding='utf-8') as f:
        fields = f.read().split()
    assert len(fields) == 1, "attenuation.txt must contain a single float value."
    try:
        alpha_agent = float(fields[0])
    except ValueError as e:
        raise AssertionError("attenuation.txt does not contain a valid float.") from e

    _, _, alpha_truth = generate_truth()
    assert np.isfinite(alpha_agent) and alpha_agent >= 0.0, (
        "Attenuation coefficient must be a finite nonnegative float."
    )
    tolerance = max(0.015, 0.5 * abs(alpha_truth))
    assert abs(alpha_agent - alpha_truth) <= tolerance, (
        f"Attenuation coefficient {alpha_agent} differs from reference "
        f"{alpha_truth} by more than {tolerance}."
    )


def test_scientific_regression_tests():
    test_file = '/home/user/test_wave.py'
    assert os.path.isfile(test_file), f"Required pytest file {test_file} not found."
    try:
        result = subprocess.run(
            [sys.executable, '-m', 'pytest', test_file, '-q', '--tb=short'],
            cwd='/home/user',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=120,
        )
    except subprocess.TimeoutExpired as e:
        raise AssertionError("test_wave.py did not complete within 120 seconds.") from e
    assert result.returncode == 0, (
        "The required scientific regression pytest did not pass:\n" + result.stdout
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
