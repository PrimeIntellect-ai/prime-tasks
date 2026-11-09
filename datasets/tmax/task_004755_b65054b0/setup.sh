#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/protein.pdb
HEADER    SYNTHETIC PROTEIN
ATOM      1  N   GLY A   1      -0.573  1.385  0.000  1.00 10.00           N
ATOM      2  CA  GLY A   1       0.000  0.000  1.500  1.00 10.00           C
ATOM      3  C   GLY A   1       1.520  0.000  3.200  1.00 10.00           C
TER
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
