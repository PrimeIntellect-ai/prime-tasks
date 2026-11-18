#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user/data/chunks

    cat << 'EOF' > /home/user/data/query.csv
0,0.5
1,-0.5
2,2.0
EOF

    cat << 'EOF' > /home/user/data/chunks/chunk_A.csv
A,0,1.0
A,1,1.0
A,2,1.0
B,0,0.0
B,1,-2.0
B,2,3.0
EOF

    cat << 'EOF' > /home/user/data/chunks/chunk_B.csv
C,0,-1.0
C,1,-1.0
C,2,-1.0
D,0,2.0
D,1,0.0
D,2,4.0
E,0,10.0
E,1,10.0
E,2,0.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
