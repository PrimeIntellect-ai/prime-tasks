#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/protein.pdb
ATOM      1  CA  ALA A   1       0.000   0.000   0.000  1.00  0.00           C  
ATOM      2  CA  ALA A   2       1.000   0.000   0.000  1.00  0.00           C  
ATOM      3  CA  ALA A   3       2.000   1.000   0.000  1.00  0.00           C  
ATOM      4  CA  ALA A   4       2.000   1.000   0.000  1.00  0.00           C  
ATOM      5  CA  ALA A   5       3.000   2.000   1.000  1.00  0.00           C  
ATOM      6  CA  ALA A   6       4.000   3.000   2.000  1.00  0.00           C  
ATOM      7  CA  ALA A   7       4.000   3.000   2.000  1.00  0.00           C  
EOF

    chmod -R 777 /home/user
