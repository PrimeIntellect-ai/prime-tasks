#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy biopython

mkdir -p /home/user

cat << 'EOF' > /home/user/sequence.fasta
>peptide
MACDT
EOF

cat << 'EOF' > /home/user/trajectory.pdb
MODEL        1
ATOM      1  N   MET A   1       0.000   0.000   0.000  1.00  0.00           N
ATOM      2  CA  MET A   1       0.000   0.000   0.000  1.00  0.00           C
ATOM      3  CA  ALA A   2       1.000   1.000   1.000  1.00  0.00           C
ATOM      4  CA  CYS A   3       2.000   2.000   2.000  1.00  0.00           C
ATOM      5  CA  ASP A   4       3.000   3.000   3.000  1.00  0.00           C
ATOM      6  CA  THR A   5       4.000   4.000   4.000  1.00  0.00           C
ENDMDL
MODEL        2
ATOM      1  N   MET A   1       0.000   0.000   0.000  1.00  0.00           N
ATOM      2  CA  MET A   1       0.100   0.000   0.000  1.00  0.00           C
ATOM      3  CA  ALA A   2       1.000   1.100   1.000  1.00  0.00           C
ATOM      4  CA  CYS A   3       2.000   2.000   2.000  1.00  0.00           C
ATOM      5  CA  ASP A   4       3.500   3.500   3.500  1.00  0.00           C
ATOM      6  CA  THR A   5       4.100   4.000   4.000  1.00  0.00           C
ENDMDL
MODEL        3
ATOM      1  N   MET A   1       0.000   0.000   0.000  1.00  0.00           N
ATOM      2  CA  MET A   1      -0.100   0.000   0.000  1.00  0.00           C
ATOM      3  CA  ALA A   2       1.000   0.900   1.000  1.00  0.00           C
ATOM      4  CA  CYS A   3       2.000   2.000   2.000  1.00  0.00           C
ATOM      5  CA  ASP A   4       2.500   2.500   2.500  1.00  0.00           C
ATOM      6  CA  THR A   5       3.900   4.000   4.000  1.00  0.00           C
ENDMDL
EOF

chmod 644 /home/user/sequence.fasta
chmod 644 /home/user/trajectory.pdb

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
