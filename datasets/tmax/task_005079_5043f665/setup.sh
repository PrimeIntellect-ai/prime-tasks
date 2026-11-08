#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils grep
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/protein.pdb
ATOM      1  N   MET A   1      27.340  24.430  -3.952  1.00 50.12           N
ATOM      2  CA  MET A   1      27.340  24.430  -2.100  1.00 50.12           C
ATOM      3  C   MET A   1      27.340  24.430   3.500  1.00 50.12           C
ATOM      4  CA  MET A   2      27.340  24.430   3.100  1.00 50.12           C
ATOM      5  CA  MET A   3      27.340  24.430   4.800  1.00 50.12           C
ATOM      6  O   MET A   3      27.340  24.430   4.100  1.00 50.12           O
ATOM      7  CA  MET A   4      27.340  24.430  -2.800  1.00 50.12           C
ATOM      8  CA  MET A   5      27.340  24.430  -0.500  1.00 50.12           C
ATOM      9  CA  MET A   6      27.340  24.430   4.120  1.00 50.12           C
ATOM     10  CA  MET A   7      27.340  24.430  12.750  1.00 50.12           C
ATOM     11  CA  MET A   8      27.340  24.430  -2.000  1.00 50.12           C
EOF

    chmod 644 /home/user/protein.pdb

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
