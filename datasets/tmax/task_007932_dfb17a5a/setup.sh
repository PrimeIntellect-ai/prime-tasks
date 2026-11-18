#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest numpy

    # Generate initial state data
    python3 -c "
import os
import random
import numpy as np
import json

os.makedirs('/home/user/data', exist_ok=True)
os.makedirs('/home/user/output', exist_ok=True)
os.makedirs('/home/user/genomic_signal', exist_ok=True)

random.seed(42)
bases = ['A', 'C', 'G', 'T']

ref_seqs = []
for _ in range(50):
    seq = ''.join(random.choices(bases, k=1200))
    ref_seqs.append(seq)

with open('/home/user/data/reference.txt', 'w') as f:
    for seq in ref_seqs:
        f.write(seq + '\n')

sample_seq_list = random.choices(bases, k=1200)
for i in range(0, 1200, 3):
    sample_seq_list[i] = 'A'
    if i+1 < 1200: sample_seq_list[i+1] = 'C'
    if i+2 < 1200: sample_seq_list[i+2] = 'G'
sample_seq = ''.join(sample_seq_list)

with open('/home/user/data/sample.txt', 'w') as f:
    f.write(sample_seq + '\n')

def calc_energy(seq):
    mapping = {'A': 1.0, 'C': -1.0, 'G': 0.5, 'T': -0.5}
    signal = np.array([mapping.get(c, 0.0) for c in seq])
    fft_vals = np.fft.fft(signal)
    P = np.real(fft_vals)**2 + np.imag(fft_vals)**2

    k_start = 360
    k_end = 420

    energy = 0.0
    for k in range(k_start + 1, k_end + 1):
        energy += (P[k-1] + P[k]) / 2.0 * (1.0 / 1200.0)
    return energy

ref_energies = [calc_energy(s) for s in ref_seqs]
ref_mean = np.mean(ref_energies)
ref_std = np.std(ref_energies, ddof=1)

sample_energy = calc_energy(sample_seq)
z_score = (sample_energy - ref_mean) / ref_std

with open('/tmp/expected_results.json', 'w') as f:
    json.dump({
        'reference_mean': float(ref_mean),
        'reference_std': float(ref_std),
        'sample_energy': float(sample_energy),
        'z_score': float(z_score)
    }, f)
"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
