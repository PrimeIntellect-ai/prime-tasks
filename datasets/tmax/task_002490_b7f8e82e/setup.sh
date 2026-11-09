#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pyarrow

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/raw_data.csv
user_id,group_id,score,name,session_id
1,100,95.5,alice,5050
2,,88.0,bob,
,102,76.2,charlie,5052
4,100,90.1,david,5053
EOF

    cat << 'EOF' > /home/user/process.py
import pandas as pd

def process_data():
    df = pd.read_csv('/home/user/data/raw_data.csv')
    # Save the file
    df.to_parquet('/home/user/processed.parquet')

if __name__ == "__main__":
    process_data()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
