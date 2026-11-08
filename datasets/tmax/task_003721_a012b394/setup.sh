#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/matrices.txt
4 12 -16 12 37 -43 -16 -43 98
1 2 3 2 4 5 3 5 6
25 15 -5 15 18 0 -5 0 11
9 3 6 3 2 -2 6 -2 29
4 2 2 2 1 1 2 1 1
EOF

    chmod -R 777 /home/user
