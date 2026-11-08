#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/input.pdb
ATOM      1  N   ALA A   1       0.000   0.000   0.000  1.00 20.00           N  
ATOM      2  CA  ALA A   1       0.000   0.000   0.000  1.00 20.00           C  
ATOM      3  CB  ALA A   1       1.000   1.000   1.000  1.00 20.00           C  
ATOM      4  CA  ALA A   2       3.000   0.000   0.000  1.00 20.00           C  
ATOM      5  N   ALA A   3       5.000   0.000   0.000  1.00 20.00           N  
ATOM      6  CA  ALA A   3       0.000   4.000   0.000  1.00 20.00           C  
TER
EOF

    chmod -R 777 /home/user
