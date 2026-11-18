#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Generate initial data
    cat << 'EOF' > /tmp/setup_data.py
import os
import csv
import tarfile

data_dir = "/home/user"
tar_path = os.path.join(data_dir, "remote_dump.tar.gz")
csv_path = os.path.join(data_dir, "transactions.csv")

os.makedirs(data_dir, exist_ok=True)

data = [
    ["transaction_id", "category", "price", "volume", "description"],
    ["T001", "Alpha", "10.50", "100", "Standard item\nBatch A"],
    ["T002", "Alpha", "12.00", "50", "Premium item"],
    ["T003", "Beta", "5.00", "200", "Bulk item\nHandle with care\nFragile"],
    ["T004", "Beta", "4.50", "100", "Discounted item"],
    ["T005", "Gamma", "100.00", "10", "Luxury item"],
    ["T006", "Delta", "20.00", "20", "Test\nNewline"],
    ["T007", "Delta", "15.00", "40", "Another item"]
]

with open(csv_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(data)

with tarfile.open(tar_path, "w:gz") as tar:
    tar.add(csv_path, arcname="transactions.csv")

os.remove(csv_path)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
