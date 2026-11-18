#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user/matrices

    # graph_A.csv - Rank 2
    cat << 'EOF' > /home/user/matrices/graph_A.csv
1,2,0,0,0
2,4,0,0,0
0,0,1,1,1
0,0,1,1,1
0,0,1,1,1
EOF

    # graph_B.csv - Rank 5
    cat << 'EOF' > /home/user/matrices/graph_B.csv
2,0,0,0,0
0,1,0,0,0
0,0,3,0,0
0,0,0,1,0
0,0,0,0,2
EOF

    # graph_C.csv - Rank 3
    cat << 'EOF' > /home/user/matrices/graph_C.csv
1,0,0,0,1
0,1,0,0,0
0,0,1,0,0
0,0,0,0,0
1,0,0,0,1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
