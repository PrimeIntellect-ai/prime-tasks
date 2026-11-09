#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust /opt/cargo

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dataset.csv
x,y
1.0,2.1
2.0,5.9
3.0,11.8
4.0,19.9
5.0,30.2
EOF

    chmod -R 777 /home/user
