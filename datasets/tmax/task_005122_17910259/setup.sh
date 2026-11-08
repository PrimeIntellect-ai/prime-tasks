#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk coreutils bash
    pip3 install pytest

    mkdir -p /home/user/graph_data

    cat << 'EOF' > /home/user/graph_data/export_1.csv
src_node,dst_node,timestamp,record_status
A,B,1700000001,ACTIVE
A,C,1700000002,ACTIVE
A,D,1700000003,ACTIVE
B,C,1700000004,ACTIVE
E,A,1700000005,ACTIVE
F,A,1700000006,ACTIVE
G,A,1700000007,ACTIVE
EOF

    cat << 'EOF' > /home/user/graph_data/export_2.csv
src_node,dst_node,timestamp,record_status
H,A,1600000000,ACTIVE
A,I,1700000008,STALE
Z,A,1700000009,CORRUPTED
B,D,1699999999,ACTIVE
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
