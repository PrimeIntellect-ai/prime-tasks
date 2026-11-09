#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user/datasets

    cat << 'EOF' > /home/user/datasets/alpha.csv
sample_id,temp,pressure,yield
A1,10.0,1.0,5.0
A2,10.0,1.0,5.0
A3,10.0,1.0,5.0
EOF

    cat << 'EOF' > /home/user/datasets/beta.csv
sample_id,temp,pressure,yield
B1,200.0,2.0,80.0
B2,200.0,2.0,80.0
B3,200.0,2.0,80.0
EOF

    cat << 'EOF' > /home/user/datasets/gamma.csv
sample_id,temp,pressure,yield
G1,100.0,1.0,50.0
G2,,1.0,50.0
G3,100.0,,50.0
G4,100.0,1.0,50.0
G5,100.0,1.0,50.0
G6,100.0,1.0,50.0
G7,100.0,1.0,50.0
G8,100.0,1.0,50.0
G9,100.0,1.0,50.0
G10,100.0,1.0,9999.0
,100.0,1.0,50.0
EOF

    cat << 'EOF' > /home/user/datasets/query.csv
sample_id,temp,pressure,yield
Q1,98.0,1.1,49.0
Q2,99.0,1.0,51.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
