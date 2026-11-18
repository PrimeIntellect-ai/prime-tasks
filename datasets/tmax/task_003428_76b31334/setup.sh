#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest numpy

    mkdir -p /app

    # Create the reference image
    convert -background white -fill black -font DejaVu-Sans -pointsize 24 label:"NUCLEOTIDE WEIGHTS: A=1.2, C=-0.8, G=0.3, T=-0.7" /app/reference_params.png

    # Create the oracle analyzer
    cat << 'EOF' > /app/oracle_analyzer
#!/usr/bin/env python3
import sys
import numpy as np

def main():
    seq = sys.argv[1]
    seed = int(sys.argv[2])
    weights = {'A': 1.2, 'C': -0.8, 'G': 0.3, 'T': -0.7}

    L = len(seq)
    orig_arr = np.array([weights[c] for c in seq])

    np.random.seed(seed)
    D_vals = []

    for _ in range(100):
        idx = np.random.choice(L, size=L, replace=True)
        arr = orig_arr[idx]

        dft = np.fft.fft(arr)
        P = np.abs(dft)**2
        sum_P = np.sum(P)
        if sum_P == 0:
            Q = np.ones(L) / L
        else:
            Q = P / sum_P

        U = 1.0 / L
        Q_safe = Q + 1e-9
        D = np.sum(Q_safe * np.log2(Q_safe / U))
        D_vals.append(D)

    D_vals.sort()
    print(f"{D_vals[94]:.4f}")

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle_analyzer

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
