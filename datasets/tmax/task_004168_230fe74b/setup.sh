#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest jupyter papermill scipy numpy biopython nbformat

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_pdb.py
import random
random.seed(42)

with open('/home/user/protein.pdb', 'w') as f:
    atom_idx = 1
    res_idx = 1
    for i in range(100):
        # Generate some synthetic B-factors
        b_n = random.gauss(20, 5)
        b_ca = random.gauss(30, 8)
        b_c = random.gauss(25, 6)
        b_o = random.gauss(28, 7)

        # Write ATOM records (fixed width per PDB spec)
        f.write(f"ATOM  {atom_idx:5d}  N   ALA A{res_idx:4d}    10.000  10.000  10.000  1.00 {b_n:5.2f}           N  \n")
        atom_idx += 1
        f.write(f"ATOM  {atom_idx:5d}  CA  ALA A{res_idx:4d}    11.000  11.000  11.000  1.00 {b_ca:5.2f}           C  \n")
        atom_idx += 1
        f.write(f"ATOM  {atom_idx:5d}  C   ALA A{res_idx:4d}    12.000  12.000  12.000  1.00 {b_c:5.2f}           C  \n")
        atom_idx += 1
        f.write(f"ATOM  {atom_idx:5d}  O   ALA A{res_idx:4d}    13.000  13.000  13.000  1.00 {b_o:5.2f}           O  \n")
        atom_idx += 1
        res_idx += 1
EOF
    python3 /home/user/generate_pdb.py

    cat << 'EOF' > /home/user/create_notebook.py
import nbformat as nbf

nb = nbf.v4.new_notebook()

code1 = """\
import numpy as np
from scipy import stats
from scipy.integrate import quad

# Parameters
pdb_file = '/home/user/protein.pdb'
"""

code2 = """\
# Parse PDB and extract B-factors for CA atoms
b_factors = []
with open(pdb_file, 'r') as f:
    for line in f:
        if line.startswith('ATOM'):
            atom_name = line[12:16].strip()
            if atom_name == 'CA':
                b_factor = float(line[60:66].strip())
                b_factors.append(b_factor)
b_factors = np.array(b_factors)
"""

code3 = """\
# Fit KDE
# BUG: bandwidth is way too small, causing numerical integration to fail/diverge
kde = stats.gaussian_kde(b_factors, bw_method=1e-5)
"""

code4 = """\
# Integrate KDE from 10 to 50
integral, error = quad(kde.evaluate, 10, 50, limit=50)

with open('/home/user/results.txt', 'w') as f:
    f.write(f"Integral: {integral}\\n")
"""

nb['cells'] = [
    nbf.v4.new_code_cell(code1),
    nbf.v4.new_code_cell(code2),
    nbf.v4.new_code_cell(code3),
    nbf.v4.new_code_cell(code4)
]

with open('/home/user/bfactor_workflow.ipynb', 'w') as f:
    nbf.write(nb, f)
EOF
    python3 /home/user/create_notebook.py

    rm /home/user/generate_pdb.py /home/user/create_notebook.py

    chmod -R 777 /home/user
