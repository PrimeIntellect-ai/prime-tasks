#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest numpy scipy h5py

    mkdir -p /app
    mkdir -p /opt/oracle

    # Generate the DTMF audio file for "4*15"
    cat << 'EOF' > /tmp/gen_audio.py
import numpy as np
from scipy.io.wavfile import write

sample_rate = 8000
duration = 0.5
pause = 0.1

def generate_tone(f1, f2, duration, sample_rate):
    t = np.linspace(0, duration, int(sample_rate * duration), False)
    tone = np.sin(f1 * 2 * np.pi * t) + np.sin(f2 * 2 * np.pi * t)
    return tone

tones = [
    (770, 1209), # 4
    (941, 1209), # *
    (697, 1209), # 1
    (770, 1336), # 5
]

audio = []
for f1, f2 in tones:
    audio.append(generate_tone(f1, f2, duration, sample_rate))
    audio.append(np.zeros(int(sample_rate * pause)))

audio_data = np.concatenate(audio)
audio_data = audio_data / np.max(np.abs(audio_data)) * 32767
write('/app/parameter.wav', sample_rate, audio_data.astype(np.int16))
EOF
    python3 /tmp/gen_audio.py
    rm /tmp/gen_audio.py

    # Create the oracle script
    cat << 'EOF' > /opt/oracle/solver_oracle.py
import sys
import h5py
import numpy as np

def solve(hdf5_path):
    D = 4.15
    with h5py.File(hdf5_path, 'r') as f:
        data = f['/data/signal'][:]
        M = np.mean(data)

    # roots of x^3 + 0*x^2 + D*x - M = 0
    coeffs = [1.0, 0.0, D, -M]
    roots = np.roots(coeffs)
    real_roots = roots[np.isreal(roots)].real
    print(f"{real_roots[0]:.5f}")

if __name__ == "__main__":
    solve(sys.argv[1])
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
