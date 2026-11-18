#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/molecule.adjlist
0 1 2 3
1 0 4 5
2 0 6
3 0 7 8
4 1
5 1
6 2 9
7 3
8 3
9 6
EOF

    chmod -R 777 /home/user
