#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv tesseract-ocr
    pip3 install pytest Pillow numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /app/tests/corpus/clean
    mkdir -p /app/tests/corpus/evil

    # Create virtual environment and install dependencies
    python3 -m venv /home/user/venv
    /home/user/venv/bin/pip install biopython numpy Pillow pytesseract

    # Generate files using Python
    cat << 'EOF' > /tmp/setup.py
import os
from PIL import Image, ImageDraw

# Generate image
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), "Simulation Parameters:\nCLASH_CUTOFF = 0.65\nTARGET_EPSILON = 1e-12\nEnsure stable reduction!", fill=(0,0,0))
img.save('/app/params_notes.png')

# Generate clean PDBs
clean_pdb = """ATOM      1  N   ALA A   1      10.000  10.000  10.000  1.00 20.00           N  
ATOM      2  CA  ALA A   1      11.000  11.000  11.000  1.00 20.00           C  
ATOM      3  C   ALA A   1      12.000  12.000  12.000  1.00 20.00           C  
ATOM      4  O   ALA A   1      13.000  13.000  13.000  1.00 20.00           O  
"""
for i in range(50):
    with open(f'/app/tests/corpus/clean/clean_{i}.pdb', 'w') as f:
        f.write(clean_pdb)

# Generate evil PDBs
clash_pdb = """ATOM      1  CA  ALA A   1      10.000  10.000  10.000  1.00 20.00           C  
ATOM      2  CB  ALA A   1      10.500  10.000  10.000  1.00 20.00           C  
"""
for i in range(20):
    with open(f'/app/tests/corpus/evil/clash_{i}.pdb', 'w') as f:
        f.write(clash_pdb)

text_pdb = """ATOM      1  CA  ALA A   1      10.000  10.000  TEXT00  1.00 20.00           C  
"""
for i in range(15):
    with open(f'/app/tests/corpus/evil/text_{i}.pdb', 'w') as f:
        f.write(text_pdb)

missing_ca_pdb = """ATOM      1  N   ALA A   1      10.000  10.000  10.000  1.00 20.00           N  
ATOM      2  C   ALA A   1      12.000  12.000  12.000  1.00 20.00           C  
ATOM      3  O   ALA A   1      13.000  13.000  13.000  1.00 20.00           O  
"""
for i in range(15):
    with open(f'/app/tests/corpus/evil/missing_ca_{i}.pdb', 'w') as f:
        f.write(missing_ca_pdb)
EOF
    python3 /tmp/setup.py

    # Create calc_com.py
    cat << 'EOF' > /home/user/calc_com.py
import sys
import numpy as np
import random

def calc_com(pdb_file):
    coords = []
    with open(pdb_file, 'r') as f:
        for line in f:
            if line.startswith('ATOM') or line.startswith('HETATM'):
                try:
                    x = float(line[30:38])
                    y = float(line[38:46])
                    z = float(line[46:54])
                    coords.append((x, y, z))
                except ValueError:
                    pass
    if not coords:
        return 0.0, 0.0, 0.0
    random.shuffle(coords)
    x = np.sum([c[0] for c in coords]) / len(coords)
    y = np.sum([c[1] for c in coords]) / len(coords)
    z = np.sum([c[2] for c in coords]) / len(coords)
    return x, y, z

if __name__ == "__main__":
    if len(sys.argv) > 1:
        x, y, z = calc_com(sys.argv[1])
        print(f"{x},{y},{z}")
EOF

    chmod -R 777 /app
    chmod -R 777 /home/user
