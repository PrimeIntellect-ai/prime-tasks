#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/train.csv
id,label,v1,v2,v3,v4,v5
1,0,0.1,0.2,0.1,0.1,0.0
2,1,0.9,0.8,0.9,1.0,0.9
3,0,0.2,0.1,0.2,0.0,0.1
error_row_1,0,0,0,0,0,0
4,1,0.8,0.9,0.8,0.9,1.0
5,0,0.1,0.1,0.1,0.1,0.1
6,1,1.0,1.0,1.0,1.0,1.0
7,0,0.3,0.3,0.2,0.1,0.2
8,1,0.7,0.7,0.8,0.9,0.8
9,0,0.0,0.0,0.0,0.0,0.0
10,1,0.9,0.9,0.9,0.9,0.9
malformed,row
11,0,0.2,0.2,0.2,0.2,0.2
12,1,0.8,0.8,0.8,0.8,0.8
13,0,0.4,0.1,0.1,0.2,0.1
14,1,0.6,0.9,0.7,0.8,0.9
EOF

    cat << 'EOF' > /home/user/test.csv
id,v1,v2,v3,v4,v5
101,0.15,0.15,0.15,0.15,0.15
102,0.85,0.85,0.85,0.85,0.85
103,0.5,0.5,0.5,0.5,0.5
EOF

    chmod -R 777 /home/user
