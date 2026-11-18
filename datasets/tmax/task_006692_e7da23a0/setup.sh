#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_task.py
import numpy as np
from scipy.integrate import solve_ivp

np.random.seed(42)

# Generate baseline distances
baseline_distances = np.random.uniform(10.0, 20.0, 10)
np.save('/home/user/baseline_distances.npy', baseline_distances)

def model(t, y):
    T1, T2 = y
    dT1 = -0.1 * (T1 - T2)
    dT2 = 0.1 * (T1 - T2) - 0.05 * (T2 - 20)
    return [dT1, dT2]

sol = solve_ivp(model, [0, 90], [1000, 300], t_eval=np.arange(0, 100, 10))
T1_true = sol.y[0]

signals = np.zeros((10, 1000))
f = np.arange(500)
for i in range(10):
    mu = 0.2 * T1_true[i]
    sigma = 0.5 * np.sqrt(T1_true[i])
    mag = np.exp(-0.5 * ((f - mu) / sigma)**2)
    mag += np.random.normal(0, 0.05, 500)
    mag = np.abs(mag)

    full_spectrum = np.zeros(1000, dtype=complex)
    full_spectrum[:500] = mag
    full_spectrum[501:] = mag[1:][::-1]

    window = np.hanning(1000)
    window[window < 0.01] = 0.01
    time_signal = np.fft.ifft(full_spectrum).real
    signals[i] = time_signal / window

np.save('/home/user/experimental_signals.npy', signals)
EOF

    python3 /tmp/setup_task.py
    rm /tmp/setup_task.py

    chmod -R 777 /home/user
