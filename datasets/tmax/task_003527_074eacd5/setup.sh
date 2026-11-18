#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest jupyter nbconvert numpy

    mkdir -p /home/user
    cat << 'EOF' > /home/user/protein.pdb
ATOM      1  N   ALA A   1      11.104  12.231  13.456  1.00  0.00           N  
ATOM      2  CA  ALA A   1      12.000  13.000  14.000  1.00  0.00           C  
ATOM      3  C   ALA A   1      13.500  12.500  13.800  1.00  0.00           C  
ATOM      4  O   ALA A   1      14.200  13.200  13.100  1.00  0.00           O  
ATOM      5  N   GLY A   2      13.900  11.300  14.300  1.00  0.00           N  
ATOM      6  CA  GLY A   2      15.200  10.700  14.100  1.00  0.00           C  
ATOM      7  C   GLY A   2      16.300  11.500  14.900  1.00  0.00           C  
ATOM      8  O   GLY A   2      17.400  11.000  15.100  1.00  0.00           O  
ATOM      9  N   SER A   3      16.000  12.700  15.400  1.00  0.00           N  
ATOM     10  CA  SER A   3      17.000  13.600  16.100  1.00  0.00           C  
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
