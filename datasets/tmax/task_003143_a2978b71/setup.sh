#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/state1.pdb
ATOM      1  CA  ALA A   1       0.000   0.000   0.000  1.00  0.00           C  
ATOM      2  CA  ALA A   2       3.000   0.000   0.000  1.00  0.00           C  
ATOM      3  CA  ALA A   3       6.000   0.000   0.000  1.00  0.00           C  
ATOM      4  CA  ALA A   4       9.000   0.000   0.000  1.00  0.00           C  
ATOM      5  CA  ALA A   5      12.000   0.000   0.000  1.00  0.00           C  
EOF

    cat << 'EOF' > /home/user/state2.pdb
ATOM      1  CA  ALA A   1       0.000   0.000   0.000  1.00  0.00           C  
ATOM      2  CA  ALA A   2       5.000   0.000   0.000  1.00  0.00           C  
ATOM      3  CA  ALA A   3      10.000   0.000   0.000  1.00  0.00           C  
ATOM      4  CA  ALA A   4      15.000   0.000   0.000  1.00  0.00           C  
ATOM      5  CA  ALA A   5      20.000   0.000   0.000  1.00  0.00           C  
EOF

    chmod -R 777 /home/user
