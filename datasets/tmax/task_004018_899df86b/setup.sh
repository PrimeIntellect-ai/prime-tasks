#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-numpy
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_pdb.py
import numpy as np

np.random.seed(42)
num_atoms = 1500
coords = np.random.rand(num_atoms, 3) * 100.0

with open('/home/user/protein_frame.pdb', 'w') as f:
    for i in range(num_atoms):
        name = "CA"
        x, y, z = coords[i]
        f.write(f"ATOM  {i+1:5d}  {name:<3s} ALA A {i+1:4d}    {x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C  \n")
EOF
    python3 /tmp/generate_pdb.py

    cat << 'EOF' > /home/user/md_analysis.py
import math
import concurrent.futures

def calc_chunk(atoms, start_i, end_i):
    energy = 0.0
    for i in range(start_i, end_i):
        xi, yi, zi = atoms[i]
        for j in range(i + 1, len(atoms)):
            xj, yj, zj = atoms[j]
            dx = xi - xj
            dy = yi - yj
            dz = zi - zj
            r2 = dx*dx + dy*dy + dz*dz
            r6 = r2 * r2 * r2
            if r6 > 0:
                energy += (1.0 / (r6 * r6)) - (1.0 / r6)
    return energy

def main():
    atoms = []
    with open('/home/user/protein_frame.pdb', 'r') as f:
        for line in f:
            if line.startswith("ATOM"):
                name = line[12:16].strip()
                if name == "CA":
                    x = float(line[30:38])
                    y = float(line[38:46])
                    z = float(line[46:54])
                    atoms.append((x, y, z))

    total_energy = 0.0
    chunk_size = 50
    futures = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        for i in range(0, len(atoms), chunk_size):
            end_i = min(i + chunk_size, len(atoms))
            futures.append(executor.submit(calc_chunk, atoms, i, end_i))

        for future in concurrent.futures.as_completed(futures):
            total_energy += future.result()

    print(f"Total Energy: {total_energy:.8f}")

if __name__ == "__main__":
    main()
EOF

    chmod -R 777 /home/user
