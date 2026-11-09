#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/nodes.csv
id,type
N001,Account
N002,Account
N003,Account
N004,Account
N005,Account
N006,Account
N007,Account
EOF

    cat << 'EOF' > /home/user/data/edges.csv
source,target,timestamp,weight
N001,N002,100,50
N001,N002,200,-10
N001,N003,150,20
N001,N003,50,10
N003,N004,300,5
N003,N005,400,15
N003,N005,450,-5
N004,N006,500,10
N002,N007,600,20
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
