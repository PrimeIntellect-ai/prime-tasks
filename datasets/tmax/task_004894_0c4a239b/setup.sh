#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest pandas numpy

    # Install Rust for all users
    export RUSTUP_HOME=/opt/rustup
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rustup /opt/cargo

    useradd -m -s /bin/bash user || true

    # Generate the initial dataset
    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
n = 50
rd_spend = np.random.uniform(10, 100, n)
total_exp = rd_spend + np.random.uniform(50, 200, n)
profit = 0.5 * (rd_spend / total_exp) * 1000 + np.random.normal(0, 50, n)

df = pd.DataFrame({
    'Company_ID': [f'COMP_{i}' for i in range(n)],
    'R&D_Spend': rd_spend,
    'Total_Expenses': total_exp,
    'Profit': profit
})
df.to_csv('/home/user/company_data.csv', index=False)
EOF

    python3 /tmp/generate_data.py

    chmod -R 777 /home/user
