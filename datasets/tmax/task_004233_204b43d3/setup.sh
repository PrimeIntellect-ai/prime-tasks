#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="$HOME/.cargo/bin:$PATH"

    mkdir -p /home/user/

    cat << 'EOF' > /home/user/create_data.py
import csv

with open('/home/user/raw_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'feature_x', 'label'])

    # Train set: 80 rows
    for i in range(1, 81):
        if i % 8 == 0:
            writer.writerow([i, '', 0]) # 10 missing
        else:
            writer.writerow([i, '10.0', 1]) # 70 values of 10.0, sum = 700, mean = 10.0

    # Test set: 20 rows
    for i in range(81, 101):
        if i % 4 == 0:
            writer.writerow([i, '', 0]) # 5 missing
        else:
            writer.writerow([i, '50.0', 1]) # 15 values of 50.0, sum = 750, mean = 50.0
EOF
    python3 /home/user/create_data.py
    rm /home/user/create_data.py

    useradd -m -s /bin/bash user || true

    # Ensure rust is available for all users
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | su - user -c "sh -s -- -y"

    chmod -R 777 /home/user
