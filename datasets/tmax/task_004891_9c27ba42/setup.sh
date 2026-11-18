#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas emcee

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/protein.fasta
>sp|P12345|PROT_TEST Test Protein
MADCQLYCGGVASDC
LQCASGGCQC
EOF

    cat << 'EOF' > /home/user/data/protein.pdb
ATOM     14  N   CYS A   2      -8.150  14.208   0.395  1.00  0.00           N  
ATOM     15  CA  CYS A   2      -7.790  12.793   0.211  1.00  0.00           C  
ATOM     16  C   CYS A   2      -8.814  11.859  -0.420  1.00  0.00           C  
ATOM     17  O   CYS A   2      -9.988  12.183  -0.589  1.00  0.00           O  
ATOM     18  CB  CYS A   2      -6.471  12.720  -0.569  1.00  0.00           C  
ATOM     19  SG  CYS A   2      -5.114  13.431   0.360  1.00  0.00           S  
ATOM     20  N   ALA A   3      -8.384  10.639  -0.651  1.00  0.00           N  
ATOM     40  N   CYS A   5      -8.150  14.208   0.395  1.00  0.00           N  
ATOM     41  CA  CYS A   5      -7.790  12.793   0.211  1.00  0.00           C  
ATOM     42  SG  CYS A   5      -5.114  13.431   0.360  1.00  0.00           S  
ATOM     55  SG  CYS A   8      -5.114  13.431   0.360  1.00  0.00           S  
EOF

    python3 -c "
import numpy as np
from scipy.integrate import odeint
import csv

S = 0.5
k = 0.12

def deriv(P, t):
    return -k * (P**2) / (1 + S)

times = np.linspace(0, 10, 20)
P0 = 100.0
P_true = odeint(deriv, P0, times).flatten()

# Add deterministic noise
np.random.seed(42)
noise = np.random.normal(0, 2.0, size=len(times))
P_obs = P_true + noise

with open('/home/user/data/kinetics.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['time', 'concentration'])
    for t, p in zip(times, P_obs):
        writer.writerow([round(t, 2), round(p, 2)])
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
