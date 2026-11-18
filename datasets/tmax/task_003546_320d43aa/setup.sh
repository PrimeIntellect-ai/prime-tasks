#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python2 curl jq nginx rustc cargo
pip3 install pytest

mkdir -p /home/user/data
mkdir -p /home/user/rust_sorter

cat << 'EOF' > /home/user/data/batch1.csv
id,timestamp,value
A1,1620000000,foo
A2,1620000050,bar
A3,1619999900,baz
EOF

cat << 'EOF' > /home/user/data/batch2.csv
id,timestamp,value
B1,1620000100,qux
B2,1619999800,quux
EOF

cat << 'EOF' > /home/user/legacy_sorter.py
import csv
import json
import os
import glob

def main():
    data_dir = '/home/user/data'
    all_rows = []

    for filepath in glob.glob(os.path.join(data_dir, '*.csv')):
        with open(filepath, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                # Convert timestamp to integer for correct sorting
                row['timestamp'] = int(row['timestamp'])
                all_rows.append(row)

    # Sort descending by timestamp
    all_rows.sort(key=lambda x: x['timestamp'], reverse=True)

    print json.dumps(all_rows)

if __name__ == '__main__':
    main()
EOF

cat << 'EOF' > /home/user/rust_sorter/Cargo.toml
[package]
name = "rust_sorter"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = "0.6"
tokio = { version = "1", features = ["full"] }
csv = "1.2"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
