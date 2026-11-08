#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import os
import random

random.seed(42)
true_mu = 42.5
true_sigma = 4.8
num_residues = 150

pdb_path = "/home/user/protein.pdb"
os.makedirs(os.path.dirname(pdb_path), exist_ok=True)

with open(pdb_path, "w") as f:
    for i in range(1, num_residues + 1):
        b_factor = random.gauss(true_mu, true_sigma)
        f.write(f"ATOM  {i*3-2:5d}  CA  ALA A{i:4d}    {0.0:8.3f}{0.0:8.3f}{0.0:8.3f}  1.00{b_factor:6.2f}           C  \n")
        noise_b = b_factor + random.uniform(5, 15)
        f.write(f"ATOM  {i*3-1:5d}  CB  ALA A{i:4d}    {1.0:8.3f}{1.0:8.3f}{1.0:8.3f}  1.00{noise_b:6.2f}           C  \n")
        noise_b2 = b_factor + random.uniform(-5, 5)
        f.write(f"ATOM  {i*3:5d}  N   ALA A{i:4d}    {-1.0:8.3f}{-1.0:8.3f}{-1.0:8.3f}  1.00{noise_b2:6.2f}           N  \n")
'

    chmod -R 777 /home/user
