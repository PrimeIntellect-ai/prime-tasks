#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /app

    # Generate system_vibration.wav
    python3 -c "
import numpy as np
import scipy.io.wavfile as wav
fs = 44100
t = np.linspace(0, 2, fs*2, endpoint=False)
signal = np.sin(2 * np.pi * 120 * t) + 0.1 * np.random.randn(len(t))
wav.write('/app/system_vibration.wav', fs, signal.astype(np.float32))
"

    # Create oracle_solver.py
    cat << 'EOF' > /app/oracle_solver.py
import sys
import numpy as np
import scipy.io.wavfile as wav

def main():
    if len(sys.argv) != 3:
        sys.exit(1)

    wav_path = sys.argv[1]
    matrix_str = sys.argv[2]

    fs, data = wav.read(wav_path)
    fft_vals = np.fft.rfft(data)
    fft_freqs = np.fft.rfftfreq(len(data), 1.0/fs)
    fd = int(round(fft_freqs[np.argmax(np.abs(fft_vals))]))

    M = [float(x) for x in matrix_str.split(',')]
    k = M[0] * M[3]
    c = M[1] + M[2]
    A = 10.0

    dt = 0.001
    steps = int(2.0 / dt)
    x = 0.0
    v = 0.0
    max_abs_x = 0.0

    for i in range(steps):
        t = i * dt
        dx = v
        dv = -k * x - c * v + A * np.sin(2 * np.pi * fd * t)

        x += dx * dt
        v += dv * dt

        if abs(x) > max_abs_x:
            max_abs_x = abs(x)

    print(f"{max_abs_x:.4f}")

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
