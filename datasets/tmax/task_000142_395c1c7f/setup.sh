#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/molecule.pdb
ATOM      1  C1  MOL     1       0.000   0.000   0.000  1.00  0.00           C  
ATOM      2  C2  MOL     1       1.500   0.000   0.000  1.00  0.00           C  
ATOM      3  O1  MOL     1       0.000   1.500   0.000  1.00  0.00           O  
EOF

    chmod -R 777 /home/user
