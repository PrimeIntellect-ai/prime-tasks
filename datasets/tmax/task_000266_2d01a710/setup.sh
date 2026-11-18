#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_edges.txt
1 2
2 3
1 4
4 5
1 5
2 4
2 5
6 7
7 8
6 8
6 9
7 9
8 9
10 11
1 10
3 4
EOF

    chmod -R 777 /home/user
