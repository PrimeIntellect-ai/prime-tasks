#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/protein.pdb
ATOM      1  N   ALA A   1      10.000  20.000   1.500  1.00 20.00           N
ATOM      2  CA  ALA A   1      10.000  20.000   2.100  1.00 20.00           C
ATOM      3  C   ALA A   1      10.000  20.000   2.500  1.00 20.00           C
ATOM      4  O   ALA A   1      10.000  20.000   2.900  1.00 20.00           O
ATOM      5  N   GLY A   2      10.000  20.000   3.500  1.00 20.00           N
ATOM      6  CA  GLY A   2      10.000  20.000   4.000  1.00 20.00           C
ATOM      7  C   GLY A   2      10.000  20.000   4.500  1.00 20.00           C
ATOM      8  O   GLY A   2      10.000  20.000   4.900  1.00 20.00           O
ATOM      9  N   SER A   3      10.000  20.000   5.500  1.00 20.00           N
ATOM     10  CA  SER A   3      10.000  20.000   6.100  1.00 20.00           C
ATOM     11  C   SER A   3      10.000  20.000   6.500  1.00 20.00           C
ATOM     12  O   SER A   3      10.000  20.000   6.900  1.00 20.00           O
ATOM     13  N   THR A   4      10.000  20.000   7.500  1.00 20.00           N
ATOM     14  CA  THR A   4      10.000  20.000   8.200  1.00 20.00           C
ATOM     15  C   THR A   4      10.000  20.000   8.500  1.00 20.00           C
ATOM     16  O   THR A   4      10.000  20.000   8.900  1.00 20.00           O
ATOM     17  N   VAL A   5      10.000  20.000   9.500  1.00 20.00           N
ATOM     18  CA  VAL A   5      10.000  20.000   9.900  1.00 20.00           C
ATOM     19  C   VAL A   5      10.000  20.000  10.500  1.00 20.00           C
ATOM     20  O   VAL A   5      10.000  20.000  10.900  1.00 20.00           O
EOF

    cat << 'EOF' > /home/user/reference_models.csv
ModelName,Slope,Intercept
AlphaHelix,1.5,0.5
BetaSheet,1.98,0.12
RandomCoil,-0.5,2.0
OmegaLoop,2.05,-0.10
EOF

    chmod -R 777 /home/user
