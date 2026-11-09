#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    # Create agent's bugged package
    mkdir -p /app/genomic_dsp/genomic_dsp

    cat << 'EOF' > /app/genomic_dsp/setup.py
from setuptools import setup, find_packages
setup(name='genomic_dsp', version='1.0.0', packages=find_packages())
EOF

    cat << 'EOF' > /app/genomic_dsp/genomic_dsp/__init__.py
from .transforms import filter_signal
EOF

    cat << 'EOF' > /app/genomic_dsp/genomic_dsp/transforms.py
# import numpy as np
# from scipy.fft import fft, ifft

def filter_signal(signal_array):
    # simple low pass + dummy cholesky for the sake of using primitive skills
    arr = np.array(signal_array)
    f = fft(arr)
    f[len(f)//2:] = 0
    smoothed = np.real(ifft(f))
    # construct a dummy positive definite matrix
    n = len(smoothed)
    A = np.eye(n) * 2.0 + np.ones((n, n)) * 0.1
    L = np.linalg.cholesky(A)
    # multiply smoothed signal by L
    out = L.dot(smoothed)
    return out.tolist()
EOF

    # Create oracle's unbugged package and script
    mkdir -p /opt/oracle/genomic_dsp

    cat << 'EOF' > /opt/oracle/genomic_dsp/__init__.py
from .transforms import filter_signal
EOF

    cat << 'EOF' > /opt/oracle/genomic_dsp/transforms.py
import numpy as np
from scipy.fft import fft, ifft

def filter_signal(signal_array):
    # simple low pass + dummy cholesky for the sake of using primitive skills
    arr = np.array(signal_array)
    f = fft(arr)
    f[len(f)//2:] = 0
    smoothed = np.real(ifft(f))
    # construct a dummy positive definite matrix
    n = len(smoothed)
    A = np.eye(n) * 2.0 + np.ones((n, n)) * 0.1
    L = np.linalg.cholesky(A)
    # multiply smoothed signal by L
    out = L.dot(smoothed)
    return out.tolist()
EOF

    cat << 'EOF' > /opt/oracle/prepare_data.py
import sys
import os
import json

# Ensure oracle uses its own unbugged version
sys.path.insert(0, '/opt/oracle')
from genomic_dsp import filter_signal

def main():
    for line in sys.stdin:
        if not line.strip():
            continue
        data = json.loads(line)
        primer = data["primer"]
        seq = data["sequence"]
        sig = data["signal"]

        start = seq.find(primer)
        if start == -1:
            print("NO_MATCH")
        else:
            end = start + len(primer) - 1
            sliced = sig[start:end+1]
            filtered = filter_signal(sliced)
            print(", ".join([f"{x:.4f}" for x in filtered]))

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
