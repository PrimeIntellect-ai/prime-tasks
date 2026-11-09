#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/sim

    cat << 'EOF' > /home/user/data/input.pdb
ATOM      1  N   ALA A   1       0.000   0.000   0.000  1.00  0.00           N  
ATOM      2  CA  ALA A   1       0.000   0.000   0.000  1.00  0.00           C  
ATOM      3  C   ALA A   1       0.000   0.000   0.000  1.00  0.00           C  
ATOM      4  O   ALA A   1       0.000   0.000   0.000  1.00  0.00           O  
ATOM      5  N   GLY A   2       3.000   4.000   0.000  1.00  0.00           N  
ATOM      6  CA  GLY A   2       3.000   4.000   0.000  1.00  0.00           C  
ATOM      7  C   GLY A   2       3.000   4.000   0.000  1.00  0.00           C  
ATOM      8  O   GLY A   2       3.000   4.000   0.000  1.00  0.00           O  
ATOM      9  N   SER A   3       0.000   4.000   0.000  1.00  0.00           N  
ATOM     10  CA  SER A   3       0.000   4.000   0.000  1.00  0.00           C  
ATOM     11  C   SER A   3       0.000   4.000   0.000  1.00  0.00           C  
ATOM     12  O   SER A   3       0.000   4.000   0.000  1.00  0.00           O  
EOF

    cat << 'EOF' > /home/user/sim/integrator.py
def simulate(k, t_end):
    # Buggy forward Euler
    y = 100.0
    t = 0.0
    dt = 0.5
    while t < t_end:
        y = y - k * y * dt
        t += dt
    return y
EOF

    chmod -R 777 /home/user
