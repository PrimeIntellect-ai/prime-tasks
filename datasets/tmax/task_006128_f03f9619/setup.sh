#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/anchors.csv
1,0.0,0.0,0.0
2,1.0,1.0,1.0
3,2.0,0.0,0.0
4,0.0,2.0,0.0
5,0.0,0.0,2.0
EOF

    cat << 'EOF' > /home/user/candidates.csv
101,0.1,0.1,0.1
102,0.9,0.9,0.9
103,1.9,0.1,0.1
104,0.1,1.9,0.1
105,0.1,0.1,1.9
106,10.0,10.0,10.0
EOF

    cat << 'EOF' > /home/user/sample_ids.txt
2
5
3
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
