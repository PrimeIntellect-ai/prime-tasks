#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv make build-essential
    pip3 install pytest

    mkdir -p /app/data
    mkdir -p /app/vendored_bio_struct_parser/bio_struct_parser
    python3 -m venv /app/venv
    /app/venv/bin/pip install --upgrade pip
    /app/venv/bin/pip install numpy scipy flask fastapi uvicorn setuptools

    # Generate files using the virtual environment's python
    /app/venv/bin/python -c '
import os
import numpy as np

# Generate synthetic PDB files
np.random.seed(42)
b_factors_A = np.random.normal(loc=20.0, scale=5.0, size=200)
b_factors_B = np.random.normal(loc=30.0, scale=6.0, size=200)

def write_pdb(filename, b_factors):
    with open(filename, "w") as f:
        for i, bf in enumerate(b_factors):
            # Write a CA atom
            f.write(f"ATOM  {i+1:5d}  CA  ALA A {i+1:4d}    {0.0:8.3f}{0.0:8.3f}{0.0:8.3f}  1.00{bf:6.2f}           C  \n")
            # Write a dummy CB atom to ensure filtering works
            f.write(f"ATOM  {i+201:5d}  CB  ALA A {i+1:4d}    {1.0:8.3f}{1.0:8.3f}{1.0:8.3f}  1.00{bf-2.0:6.2f}           C  \n")

write_pdb("/app/data/proteinA.pdb", b_factors_A)
write_pdb("/app/data/proteinB.pdb", b_factors_B)

# Create vendored package
setup_py = """
from setuptools import setup, find_packages
setup(
    name="bio_struct_parser",
    version="1.0.0",
    packages=find_packages(),
)
"""
with open("/app/vendored_bio_struct_parser/setup.py", "w") as f:
    f.write(setup_py)

init_py = """
def parse_pdb(filepath):
    atoms = []
    with open(filepath, "r") as f:
        for line in f:
            if line.startswith("ATOM"):
                atom_name = line[12:16].strip()
                b_factor = float(line[60:66].strip())
                atoms.append({"atom_name": atom_name, "b_factor": b_factor})
    return atoms
"""
with open("/app/vendored_bio_struct_parser/bio_struct_parser/__init__.py", "w") as f:
    f.write(init_py)

makefile_content = "install:\n\t/app/venv/bin/pip insatll .\n"
with open("/app/vendored_bio_struct_parser/Makefile", "w") as f:
    f.write(makefile_content)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
