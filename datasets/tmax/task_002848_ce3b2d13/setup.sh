#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install --default-timeout=100 pytest numpy pyinstaller

    mkdir -p /app
    espeak -w /app/system_recording.wav "The calibration epsilon is one e minus five. The perturbation seed is forty two."

    cat << 'EOF' > /tmp/oracle.py
#!/usr/bin/env python3
import sys
import numpy as np

def main():
    input_bytes = sys.stdin.buffer.read(4096)
    if len(input_bytes) != 4096:
        sys.exit(1)

    x = np.frombuffer(input_bytes, dtype=np.float32)
    X = np.fft.rfft(x)
    P = np.abs(X)**2

    np.random.seed(42)
    noise = np.random.uniform(0, 1, size=513).astype(np.float32)

    P_noisy = P + noise
    P_stable = np.maximum(P_noisy, 1e-5).astype(np.float32)

    sys.stdout.buffer.write(P_stable.tobytes())

if __name__ == '__main__':
    main()
EOF

    pyinstaller --onefile /tmp/oracle.py --distpath /app --name oracle_augment
    rm -rf /tmp/oracle.py /app/oracle_augment.spec build

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
