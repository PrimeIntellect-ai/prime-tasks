#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/input.pdb
ATOM      1  CA  ALA A   1       1.000   1.000   1.000  1.00  0.00           C
ATOM      2  CA  ALA A   2       2.000   2.000   2.000  1.00  0.00           C
ATOM      3  CA  ALA A   3       3.000   3.000   3.000  1.00  0.00           C
ATOM      4  CA  ALA A   4       4.000   4.000   4.000  1.00  0.00           C
ATOM      5  CA  ALA A   5       6.000   0.000   0.000  1.00  0.00           C
ATOM      6  CA  ALA A   6       7.000   3.000   0.000  1.00  0.00           C
ATOM      7  CA  ALA A   7       8.000   0.000   4.000  1.00  0.00           C
ATOM      8  CA  ALA A   8       9.000   5.000   5.000  1.00  0.00           C
EOF

    chmod -R 777 /home/user
