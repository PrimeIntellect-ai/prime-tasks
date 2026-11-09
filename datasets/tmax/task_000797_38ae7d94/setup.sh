#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/profiler

    cat << 'EOF' > /home/user/data/input.pdb
ATOM      1  CA  ALA A   1      10.000  10.000   0.000  1.00  0.00           C  
ATOM      2  CA  ALA A   2      20.000  20.000   0.000  1.00  0.00           C  
ATOM      3  CA  ALA A   3      30.000  30.000   0.000  1.00  0.00           C  
ATOM      4  CA  ALA A   4      40.000  40.000   0.000  1.00  0.00           C  
EOF

    cd /home/user/profiler
    go mod init profiler

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
