#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ cmake make
    pip3 install pytest scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/empirical.csv
k,p
0,0.10
1,0.30
2,0.40
3,0.15
4,0.05
EOF

    chmod -R 777 /home/user
