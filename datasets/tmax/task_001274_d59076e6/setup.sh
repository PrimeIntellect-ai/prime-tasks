#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /home/user/pdb_data/

cat << 'EOF' > /home/user/pdb_data/mol1.pdb
ATOM      1  N   GLY A   1       1.000   2.000   3.000  1.00  0.00           N
ATOM      2  CA  GLY A   1       2.000   1.000   4.000  1.00  0.00           C
ATOM      3  C   GLY A   1       3.000   4.000   7.000  1.00  0.00           C
ATOM      4  O   GLY A   1       4.000   3.000   8.000  1.00  0.00           O
EOF

cat << 'EOF' > /home/user/pdb_data/mol2.pdb
HETATM    1  C   UNK     1       1.000   1.000   2.000  1.00  0.00           C
HETATM    2  C   UNK     1       2.000   2.000   4.000  1.00  0.00           C
HETATM    3  C   UNK     1       3.000   3.000   6.000  1.00  0.00           C
HETATM    4  C   UNK     1       4.000   4.000   8.000  1.00  0.00           C
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
