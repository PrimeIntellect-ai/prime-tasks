#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential libhdf5-dev
    pip3 install pytest h5py numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/cov_matrix.txt
2.0 0.8 0.4 0.2
0.8 2.0 0.8 0.4
0.4 0.8 2.0 0.8
0.2 0.4 0.8 2.0
EOF

    chmod -R 777 /home/user
