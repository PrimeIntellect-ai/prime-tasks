#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy pandas

    # Create user
    useradd -m -s /bin/bash user || true

    # Generate data files
    python3 -c "
import os
import numpy as np
import pandas as pd

os.makedirs('/home/user/data', exist_ok=True)

# Generate sequences.fasta
fasta_content = ''
for i in range(1, 11):
    fasta_content += f'>protein_{i:02d} description\n'
    fasta_content += 'ACDEFGHIKLMNPQRSTVWY\n'
with open('/home/user/data/sequences.fasta', 'w') as f:
    f.write(fasta_content)

# Generate basis.csv
wavelengths = np.arange(190, 261, 1)
alpha = np.sin((wavelengths - 190) / 10.0)**2
beta = np.cos((wavelengths - 190) / 10.0)**2
coil = np.exp(-((wavelengths - 220)**2) / 200.0)

basis_df = pd.DataFrame({
    'wavelength': wavelengths,
    'alpha': alpha,
    'beta': beta,
    'coil': coil
})
basis_df.to_csv('/home/user/data/basis.csv', index=False)

# Generate spectra.csv
np.random.seed(42)
spectra_records = []
true_coeffs = {}
for i in range(1, 11):
    seq_id = f'protein_{i:02d}'
    c = np.random.rand(3)
    c = c / np.sum(c)
    true_coeffs[seq_id] = c

    intensity = c[0]*alpha + c[1]*beta + c[2]*coil
    intensity += np.random.normal(0, 0.01, size=len(wavelengths))

    for w, I in zip(wavelengths, intensity):
        spectra_records.append({'seq_id': seq_id, 'wavelength': w, 'intensity': I})

spectra_df = pd.DataFrame(spectra_records)
spectra_df.to_csv('/home/user/data/spectra.csv', index=False)
"

    chmod -R 777 /home/user
