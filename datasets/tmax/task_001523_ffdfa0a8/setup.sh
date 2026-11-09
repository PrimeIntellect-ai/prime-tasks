#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest numpy

    mkdir -p /home/user/data /home/user/scripts

    cat << 'EOF' > /home/user/data/input.fasta
>seq1
ACGTACGT
>seq2
AAAA
>seq3
CGCGCGCG
>seq4
TTTTTTTT
>seq5
ATGCATGC
EOF

    cat << 'EOF' > /home/user/scripts/fft_power.py
#!/usr/bin/env python3
import argparse
import numpy as np

parser = argparse.ArgumentParser()
parser.add_argument("--signal", type=str, required=True)
args = parser.add_argument_group()

def main():
    args = parser.parse_args()
    try:
        signal = np.array([float(x) for x in args.signal.split(',')])
        fft_vals = np.abs(np.fft.fft(signal))
        # just return the mean of the FFT magnitudes as a dummy spectral feature
        power = np.mean(fft_vals)
        print(f"{power:.6f}")
    except:
        print("0.000000")

if __name__ == "__main__":
    main()
EOF
    chmod +x /home/user/scripts/fft_power.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
