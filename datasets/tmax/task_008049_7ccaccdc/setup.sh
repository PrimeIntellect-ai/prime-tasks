#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/molecule_graph.txt
NODES 10
0 -1.0 0.0 0.0
1 -2.0 1.0 0.0
2 -0.5 -1.0 0.0
3 0.5 1.0 0.0
4 1.5 0.5 0.0
5 2.0 -0.5 0.0
6 -1.5 -1.5 0.0
7 0.1 -0.1 0.0
8 1.0 2.0 0.0
9 -3.0 0.0 0.0
EDGES 11
0 1
0 2
1 9
1 6
2 6
3 4
4 5
3 8
0 3
2 7
7 5
EOF

    chmod -R 777 /home/user
