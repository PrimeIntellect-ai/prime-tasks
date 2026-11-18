#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/nodes.csv
1,1
2,1
3,1
4,1
5,1
10,2
11,2
12,2
EOF

    cat << 'EOF' > /home/user/edges.csv
1,2,1
1,10,2
2,10,2
3,1,1
3,11,2
1,11,2
4,5,1
4,12,2
5,10,2
2,3,1
2,11,2
EOF

    cat << 'EOF' > /home/user/.expected_matches.csv
1,2,10
2,3,11
3,1,11
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
