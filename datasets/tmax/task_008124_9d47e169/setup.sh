#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust system-wide
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust /opt/cargo
    ln -s /opt/cargo/bin/* /usr/local/bin/

    # Create user
    useradd -m -s /bin/bash user || true

    # Create input data
    cat << 'EOF' > /home/user/embeddings.csv
1.0,2.0,3.0
4.0,NaN,6.0
10.0,10.0,10.0
-1.0,-2.0,-3.0
0.5,0.5,0.5
EOF

    chmod -R 777 /home/user
