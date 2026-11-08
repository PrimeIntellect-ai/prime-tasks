#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import numpy as np
from scipy.io import wavfile

def get_laplacian(n):
    L = np.zeros((n, n))
    for i in range(n):
        L[i, i] = 2
        L[i, (i - 1) % n] = -1
        L[i, (i + 1) % n] = -1
    return L

def rk4_step(C, dt, L, k, alpha):
    def f(C_val):
        return -k * (L @ C_val) + alpha * C_val * (1 - C_val)

    k1 = f(C)
    k2 = f(C + 0.5 * dt * k1)
    k3 = f(C + 0.5 * dt * k2)
    k4 = f(C + dt * k3)

    return C + (dt / 6.0) * (k1 + 2*k2 + 2*k3 + k4)

def compute_reference_mean():
    wav_path = '/app/init_state.wav'
    assert os.path.exists(wav_path), f"Audio file {wav_path} is missing."

    samplerate, data = wavfile.read(wav_path)
    # Extract the first sample of each channel
    C = data[0, :].astype(np.float64)

    L = get_laplacian(10)
    k = 0.5
    alpha = 0.1

    t = 0.0
    dt = 0.1

    while t < 10.0:
        current_dt = dt
        if t + current_dt > 10.0:
            current_dt = 10.0 - t

        C_new = rk4_step(C, current_dt, L, k, alpha)
        max_change = np.max(np.abs(C_new - C))

        if max_change > 0.05:
            dt /= 2.0
            dt = max(dt, 0.001)
            # Recompute step
            continue

        C = C_new
        t += current_dt

        if max_change < 0.01:
            dt *= 2.0
            dt = min(dt, 0.1)

    return np.mean(C)

def test_final_mean_concentration():
    output_file = "/home/user/final_mean.txt"
    assert os.path.exists(output_file), f"Output file {output_file} does not exist."

    with open(output_file, "r") as f:
        content = f.read().strip()

    try:
        agent_val = float(content)
    except ValueError:
        pytest.fail(f"Could not parse the content of {output_file} as a float. Content: '{content}'")

    reference_val = compute_reference_mean()
    diff = abs(agent_val - reference_val)

    threshold = 0.005
    assert diff <= threshold, (
        f"Agent's final mean concentration {agent_val} differs from the reference {reference_val} "
        f"by {diff}, which exceeds the threshold of {threshold}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
