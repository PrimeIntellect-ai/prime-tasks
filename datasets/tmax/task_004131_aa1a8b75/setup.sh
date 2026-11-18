#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import numpy as np

fasta_content = """>Variant_1
ACDEF
>Variant_2
GHIJK
>Variant_3
LMNOP
>Variant_4
QRSTU
>Variant_5
VWXYZ
"""

with open('/home/user/proteins.fasta', 'w') as f:
    f.write(fasta_content)

def get_spectrum(seq):
    x = np.linspace(0, 100, 1000)
    spec = np.zeros_like(x)
    for aa in seq:
        mu = ord(aa)
        spec += np.exp(-((x - mu)**2) / (2 * (2.0**2)))
    return spec

seqs = ["ACDEF", "GHIJK", "LMNOP", "QRSTU", "VWXYZ"]
spectra = [get_spectrum(s) for s in seqs]

true_weights = [1.5, 0.0, 0.8, 2.2, 0.0]
exp_spec = sum(w * s for w, s in zip(true_weights, spectra))

np.random.seed(42)
noise = np.random.normal(0, 0.05, 1000)
exp_spec += noise

np.save('/home/user/exp_spectrum.npy', exp_spec)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
