#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    # Create directories
    mkdir -p /app/bin

    # Generate the audio file
    espeak -w /app/voicenote.wav "Note for the energy evaluator: only count Alanine, Valine, Isoleucine, and Leucine as hydrophobic. Ignore Methionine, Phenylalanine, Tyrosine, and Tryptophan. Polar count must include Cysteine. The baseline shift constant is four point two."

    # Create the oracle evaluator
    cat << 'EOF' > /app/bin/oracle_evaluator
#!/usr/bin/env python3
import sys
import math

def solve():
    seq = sys.argv[1]
    x = float(sys.argv[2])
    y = float(sys.argv[3])
    z = float(sys.argv[4])

    # Audio rules: 
    # Hydrophobic: A, V, I, L (Ignore M, F, Y, W)
    # Polar: S, T, N, Q, + C (Cysteine added)
    # Charged: R, H, K, D, E
    # Baseline: 4.2

    h_count = sum(1 for c in seq if c in 'AVIL')
    p_count = sum(1 for c in seq if c in 'STNQC')
    c_count = sum(1 for c in seq if c in 'RHKDE')

    # Log-sum-exp trick
    m = max(x, y, z)
    lse = m + math.log(math.exp(x - m) + math.exp(y - m) + math.exp(z - m))

    energy = (x * h_count) + (y * p_count) + (z * c_count) + lse + 4.2
    print(f"{energy:.4f}")

if __name__ == '__main__':
    solve()
EOF
    chmod +x /app/bin/oracle_evaluator

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
