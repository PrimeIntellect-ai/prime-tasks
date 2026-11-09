#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/input_data.csv
timestamp,S1_T,S1_H,S2_T,S2_H
100,20.0,50.0,22.0,55.0
110,,51.0,22.5,
120,21.0,,23.0,56.0
130,,,23.5,57.0
EOF

    chmod -R 777 /home/user
