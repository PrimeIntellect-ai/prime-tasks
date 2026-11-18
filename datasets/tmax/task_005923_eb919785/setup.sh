#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.pdb
ATOM      1  N   VAL A   1       0.000   0.000   0.000  1.00 20.00           N
ATOM      2  CA  VAL A   1       1.450   0.000   0.000  1.00 20.00           C
ATOM      3  C   VAL A   1       1.950   1.500   0.000  1.00 20.00           C
ATOM      4  O   VAL A   1       1.300   2.500   0.000  1.00 20.00           O
ATOM      5  CB  VAL A   1       2.000  -0.800  -1.000  1.00 20.00           C
ATOM      6  CG1 VAL A   1       3.500  -0.800  -1.000  1.00 20.00           C
ATOM      7  CG2 VAL A   1       1.500  -2.200  -1.000  1.00 20.00           C
EOF

    chmod -R 777 /home/user
