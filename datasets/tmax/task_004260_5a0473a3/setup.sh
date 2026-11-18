#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/q_matrix.csv
-0.84,0.21,0.42,0.21
0.18,-0.75,0.27,0.30
0.45,0.15,-0.90,0.30
0.12,0.48,0.24,-0.84
EOF

    chmod -R 777 /home/user
