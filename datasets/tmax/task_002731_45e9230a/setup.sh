#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest numpy scipy

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/target_dist.wav "8 2 4 1 5 7 3 9 6 1"

    # Create the oracle processor
    cat << 'EOF' > /app/oracle_processor.py
#!/usr/bin/env python3
import sys
import numpy as np
from scipy.linalg import toeplitz, svd
from scipy.spatial.distance import jensenshannon

def main():
    if len(sys.argv) != 2:
        sys.exit(1)

    # Parse input
    x = np.array([float(v) for v in sys.argv[1].split(',')])

    # Step 1 & 2: FFT and get first 10 magnitudes
    X = np.fft.fft(x)
    M = np.abs(X[:10])

    # Step 3: Toeplitz matrix
    C = toeplitz(M)

    # Step 4: SVD
    _, S, _ = svd(C)

    # Step 5: Normalize to P
    P = S / np.sum(S)

    # Step 1 (Audio): Ground truth sequence Q
    q_seq = np.array([8, 2, 4, 1, 5, 7, 3, 9, 6, 1], dtype=float)
    Q = q_seq / np.sum(q_seq)

    # Step 6: Jensen-Shannon Divergence
    js_dist = jensenshannon(P, Q, base=np.e)
    js_div = js_dist ** 2

    # Output formatted to 6 decimal places
    print(f"{js_div:.6f}")

if __name__ == "__main__":
    main()
EOF

    chmod +x /app/oracle_processor.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
