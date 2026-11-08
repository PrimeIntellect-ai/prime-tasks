#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/structure.pdb
ATOM      1  N   ALA A   1      10.000  10.000  11.000  1.00  0.00           N  
ATOM      2  CA  ALA A   1      10.000  10.000  10.000  1.00  0.00           C  
ATOM      3  C   ALA A   1      10.000  10.000   9.000  1.00  0.00           C  
ATOM      4  CA  ALA A   2      13.000  10.000  10.000  1.00  0.00           C  
ATOM      5  CA  ALA A   3      15.000  12.000  10.000  1.00  0.00           C  
ATOM      6  CA  ALA A   4      15.000  15.000  10.000  1.00  0.00           C  
ATOM      7  CA  ALA A   5      12.000  17.000  10.000  1.00  0.00           C  
ATOM      8  CA  ALA A   6      10.000  13.000  10.000  1.00  0.00           C  
ATOM      9  CA  ALA A   7       8.000  12.000  14.000  1.00  0.00           C  
ATOM     10  CA  ALA A   8       8.000   9.000  15.000  1.00  0.00           C  
ATOM     11  CA  ALA A   9      10.000   8.000  17.000  1.00  0.00           C  
ATOM     12  CA  ALA A  10      13.000   8.000  18.000  1.00  0.00           C  
ATOM     13  CA  ALA A  11      16.000   9.000  17.000  1.00  0.00           C  
ATOM     14  CA  ALA A  12      17.000  14.000  10.000  1.00  0.00           C  
EOF

    chmod -R 777 /home/user
