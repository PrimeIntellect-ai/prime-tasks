#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/graph_A.txt
0 1 1.0
1 2 1.0
2 3 1.0
3 4 1.0
4 0 1.0
0 5 1.0
5 6 1.0
6 7 1.0
7 8 1.0
8 5 1.0
2 7 1.0
EOF

    cat << 'EOF' > /home/user/graph_B.txt
0 1 1.0
1 2 1.0
2 3 1.0
3 4 1.0
4 0 1.0
0 5 1.0
5 6 1.0
6 7 1.0
7 8 1.0
8 5 1.0
2 7 0.001
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
