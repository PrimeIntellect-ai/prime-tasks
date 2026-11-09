#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/get_freq.py
import sys
import numpy as np

try:
    data = np.genfromtxt(sys.argv[1], delimiter=',', skip_header=1)
    t = data[:, 0]
    v = data[:, 1]

    n = len(v)
    dt = t[1] - t[0]
    freqs = np.fft.fftfreq(n, d=dt)
    fft_vals = np.abs(np.fft.fft(v))

    # ignore DC component
    fft_vals[0] = 0

    idx = np.argmax(fft_vals)
    dom_freq = abs(freqs[idx])

    print(f"{dom_freq:.2f}")
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
EOF
    chmod +x /home/user/get_freq.py

    python3 -c "
import numpy as np
t = np.arange(0, 2.0, 0.01)
v = 2.0 * np.sin(2 * np.pi * 5.0 * t) + 0.5 * np.sin(2 * np.pi * 15.0 * t)
pairs = [f'{time:.2f}_{val:.4f}' for time, val in zip(t, v)]
with open('/home/user/raw_sensor.dat', 'w') as f:
    f.write(' '.join(pairs) + '\n')
"

    echo "5.00" > /home/user/reference.txt

    chmod -R 777 /home/user
