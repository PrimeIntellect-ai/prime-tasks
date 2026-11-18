#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/protein.pdb
ATOM      1  N   ALA A   1      11.104   6.134  -6.504  1.00  0.00           N  
ATOM      2  CA  ALA A   1      11.639   6.071  -5.147  1.00  0.00           C  
ATOM      3  C   ALA A   1      13.111   6.464  -5.187  1.00  0.00           C  
ATOM      4  O   ALA A   1      13.916   5.660  -4.708  1.00  0.00           O  
ATOM      5  CB  ALA A   1      11.365   4.685  -4.550  1.00  0.00           C  
ATOM      6  N   GLY A   2      13.468   7.653  -5.658  1.00  0.00           N  
ATOM      7  CA  GLY A   2      14.856   8.067  -5.719  1.00  0.00           C  
ATOM      8  C   GLY A   2      15.753   7.019  -6.368  1.00  0.00           C  
ATOM      9  O   GLY A   2      16.968   7.199  -6.393  1.00  0.00           O  
ATOM     10  N   LEU A   3      15.158   5.918  -6.864  1.00  0.00           N  
ATOM     11  CA  LEU A   3      15.908   4.862  -7.535  1.00  0.00           C  
ATOM     12  C   LEU A   3      16.326   3.784  -6.539  1.00  0.00           C  
EOF

    chmod -R 777 /home/user
