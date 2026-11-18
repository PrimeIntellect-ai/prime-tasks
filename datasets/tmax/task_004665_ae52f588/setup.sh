#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/enzyme.pdb
ATOM      1  N   ALA A   1      10.000  10.000  10.000  1.00  0.00           N
ATOM      2  CA  ALA A   1      10.000  10.000  15.000  1.00  0.00           C
ATOM      3  C   ALA A   1      10.000  10.000  20.000  1.00  0.00           C
ATOM      4  O   ALA A   1      10.000  10.000  25.000  1.00  0.00           O
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
