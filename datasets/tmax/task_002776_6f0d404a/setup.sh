#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest numpy

    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
    export PATH=/opt/cargo/bin:$PATH
    chmod -R 777 /opt/rust /opt/cargo

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np

np.random.seed(42)

def generate_data():
    data = []
    expected_traces = []

    alpha = 0.01

    for i in range(100):
        if i % 10 == 0:
            base_val = np.random.randn()
            M = np.full((5, 5), base_val) + np.random.randn(5, 5) * 1e-5
        else:
            M = np.random.randn(5, 5)

        data.append(M.flatten())

        G = np.zeros((5, 5))
        for r in range(1, 5):
            G[r, :] = M[r, :] - M[r-1, :]

        C = G.T @ G
        C_reg = C + alpha * np.eye(5)

        L = np.linalg.cholesky(C_reg)
        trace_L = np.trace(L)
        expected_traces.append(trace_L)

    np.savetxt('/home/user/dataset.csv', data, delimiter=',', fmt='%.6f')

    with open('/home/user/expected_features.txt', 'w') as f:
        for t in expected_traces:
            f.write(f"{t:.4f}\n")

if __name__ == '__main__':
    generate_data()
EOF

    python3 /tmp/setup.py
    chmod -R 777 /home/user
