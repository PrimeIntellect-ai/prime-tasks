#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy matplotlib biopython

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/input
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/input/protein.fasta
>mock_protein
ACDEFGHIKL
EOF

    cat << 'EOF' > /home/user/input/protein.pdb
ATOM      1  CA  ALA A   1      10.000  10.000  10.000  1.00 20.00           C  
ATOM      2  CA  CYS A   2      11.000  12.000  10.000  1.00 20.00           C  
ATOM      3  CA  ASP A   3      12.000  14.000  11.000  1.00 20.00           C  
ATOM      4  CA  GLU A   4      13.000  15.000  13.000  1.00 20.00           C  
ATOM      5  CA  PHE A   5      11.000  16.000  15.000  1.00 20.00           C  
ATOM      6  CA  GLY A   6       9.000  17.000  14.000  1.00 20.00           C  
ATOM      7  CA  HIS A   7       8.000  15.000  12.000  1.00 20.00           C  
ATOM      8  CA  ILE A   8       7.000  13.000  11.000  1.00 20.00           C  
ATOM      9  CA  LYS A   9       8.000  11.000  10.000  1.00 20.00           C  
ATOM     10  CA  LEU A  10       9.000  10.000   9.000  1.00 20.00           C  
EOF

    chmod -R 777 /home/user
