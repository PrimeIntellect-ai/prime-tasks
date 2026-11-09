#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Create user
    useradd -m -s /bin/bash user || true

    # Create raw_metrics.csv
    cat << 'EOF' > /home/user/raw_metrics.csv
timestamp,server_id,cpu_usage,memory_bytes
1672531200,srv1,45.5,16000000000
1672531230,srv1,92.0,16500000000
1672531245,srv2,20.0,8000000000
1672531300,srv1,95.5,17000000000
1672531499,srv1,80.0,15000000000
1672531500,srv1,91.0,16000000000
1672531510,srv2,98.5,10000000000
1672531799,srv2,50.0,9000000000
EOF

    # Install Rust for the user as well, or just make sure it's accessible
    # Actually, installing it system-wide or making sure the user has it in PATH is good.
    # Apptainer runs as the calling user by default, so installing it in a shared location or just for root might not be enough if the user doesn't have it.
    # Let's install rust for the 'user' account as well, or just set RUSTUP_HOME and CARGO_HOME to a shared dir.
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    chmod -R 777 /opt/rust
    ln -s /opt/rust/bin/* /usr/local/bin/

    chown user:user /home/user/raw_metrics.csv
    chmod -R 777 /home/user
