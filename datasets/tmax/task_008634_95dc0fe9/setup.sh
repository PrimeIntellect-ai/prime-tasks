#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential cmake pkg-config libssl-dev clang
    pip3 install pytest h5py numpy

    useradd -m -s /bin/bash user || true

    # Generate the initial HDF5 data
    cat << 'EOF' > /tmp/setup_data.py
import h5py
import numpy as np

def generate_data():
    with h5py.File('/home/user/raw_molecules.h5', 'w') as f:
        grp = f.create_group('graphs')

        # graph_0: 4-node cycle
        A0 = np.array([
            [0, 1, 0, 1],
            [1, 0, 1, 0],
            [0, 1, 0, 1],
            [1, 0, 1, 0]
        ], dtype=np.float64)
        grp.create_dataset('graph_0', data=A0)

        # graph_1: Instability test
        A1 = np.array([
            [0, -2, 1],
            [-2, 0, 1],
            [1, 1, 0]
        ], dtype=np.float64)
        grp.create_dataset('graph_1', data=A1)

if __name__ == "__main__":
    generate_data()
EOF

    python3 /tmp/setup_data.py

    # Install Rust
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    ln -s /opt/cargo/bin/* /usr/local/bin/
    chmod -R 777 /opt/rust /opt/cargo

    chmod -R 777 /home/user
