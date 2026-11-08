#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libeigen3-dev
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/graph.txt
5
0 1
0 2
1 2
2 3
3 4
4 0
EOF

    chmod -R 777 /home/user
