#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential binutils
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/edges.csv
0,0,1.0
1,1,1.0
2,2,1.0
3,3,1.0
4,4,1.0
0,1,1.0
1,0,1.0
0,2,1.0
2,0,1.0
0,3,1.0
3,0,1.0
0,4,1.0
4,0,1.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
