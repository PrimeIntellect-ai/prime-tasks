#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/nodes.csv
Alice,25,1
Bob,30,2
Charlie,35,3
David,40,4
Eve,45,5
Frank,50,6
EOF

    cat << 'EOF' > /home/user/data/edges.csv
1600000000,0.54,1,2
1600000001,0.12,2,3
1600000002,0.99,3,1
1600000003,0.45,3,4
1600000004,0.22,4,5
1600000005,0.11,5,3
1600000006,0.88,5,6
1600000007,0.77,6,4
1600000008,0.66,1,2
1600000009,0.55,3,3
EOF

    chmod -R 777 /home/user
