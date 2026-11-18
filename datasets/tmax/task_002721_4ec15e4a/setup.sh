#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data/pdb

    cat << 'EOF' > /home/user/raw_data/sequences.fasta
>1abc
ALA
>2xyz
G
>3mno
ACDEFGHIKLMNPQRSTVWY
EOF

    cat << 'EOF' > /home/user/raw_data/pdb/1abc.pdb
ATOM      1  CA  ALA A   1      10.000  10.000  10.000  1.00  0.00           C
ATOM      2  CA  ALA A   2      10.000  14.000  10.000  1.00  0.00           C
ATOM      3  CA  ALA A   3      10.000  10.000  13.000  1.00  0.00           C
EOF

    cat << 'EOF' > /home/user/raw_data/pdb/2xyz.pdb
ATOM      1  CA  GLY A   1       5.000   5.000   5.000  1.00  0.00           C
EOF

    cat << 'EOF' > /home/user/raw_data/pdb/3mno.pdb
ATOM      1  CA  MET A   1       0.000   0.000   0.000  1.00  0.00           C
ATOM      2  CA  MET A   2       2.000   0.000   0.000  1.00  0.00           C
ATOM      3  N   MET A   3       5.000   5.000   5.000  1.00  0.00           N
EOF

    chmod -R 777 /home/user
