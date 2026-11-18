#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    export RUSTUP_HOME=/opt/rustup
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/cargo /opt/rustup

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/edges.csv
source_node,target_node,timestamp,weight
A,B,1000,10
A,C,1001,20
A,D,1002,5
B,C,1003,15
C,D,1004,8
E,A,1005,30
F,E,1006,25
G,H,1007,50
I,J,1008,12
K,K,1009,20
L,M,1010,invalid_weight
M,N,1011,100
N,O,1012,14
A,G,1013,10
B,F,1014,5
Z,A,1015,100
EOF

    chmod -R 777 /home/user
