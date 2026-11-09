#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ cmake make libeigen3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/artifacts.csv
1,10,0.5,1.2,0.1
2,,0.1,NaN,0.9
3,1.5,0.1,0.2,0.3
NaN,5,0.1,0.2,0.3
5,2,1.0,1.0,1.0
6,0,0.0,0.0,0.0
7,-1,0.5,0.5,0.5
EOF

    cat << 'EOF' > /home/user/data/weights.txt
0.5,1.5,0.2,0.8
EOF

    chmod -R 777 /home/user
