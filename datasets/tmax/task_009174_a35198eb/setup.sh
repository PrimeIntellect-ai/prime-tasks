#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest jupyter nbconvert numpy scipy

    mkdir -p /home/user/workspace
    cat << 'EOF' > /home/user/workspace/input.pdb
ATOM      1  N   ALA A   1       0.000   0.000   0.000  1.00  0.00           N
ATOM      2  CA  ALA A   1       0.000   0.000   0.000  1.00  0.00           C
ATOM      3  C   ALA A   1       0.000   0.000   0.000  1.00  0.00           C
ATOM      4  CA  ALA A   2       6.000   0.000   0.000  1.00  0.00           C
ATOM      5  CA  ALA A   3       0.000   6.000   0.000  1.00  0.00           C
ATOM      6  CA  ALA A   4       0.000   0.000   6.000  1.00  0.00           C
ATOM      7  CA  ALA A   5       6.000   6.000   0.000  1.00  0.00           C
ATOM      8  CA  ALA A   6       6.000   0.000   6.000  1.00  0.00           C
ATOM      9  CA  ALA A   7       0.000   6.000   6.000  1.00  0.00           C
ATOM     10  CA  ALA A   8       6.000   6.000   6.000  1.00  0.00           C
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
