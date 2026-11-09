#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest numpy

    # Install Rust
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/opt/cargo/bin:$PATH"
    chmod -R 777 /opt/rust /opt/cargo

    # Create directories
    mkdir -p /home/user/data
    mkdir -p /home/user/project

    # Generate data
    python3 -c "
import numpy as np
np.random.seed(42)
data = np.random.rand(1000, 50)
np.savetxt('/home/user/data/embeddings.csv', data, delimiter=',')
"

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
