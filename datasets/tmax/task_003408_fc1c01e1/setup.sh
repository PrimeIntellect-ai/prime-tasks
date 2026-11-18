#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget
    pip3 install pytest pandas

    mkdir -p /app
    cd /app
    wget https://files.pythonhosted.org/packages/source/t/tinydb/tinydb-4.8.0.tar.gz
    tar -xzf tinydb-4.8.0.tar.gz
    rm tinydb-4.8.0.tar.gz

    # Introduce the bug
    sed -i 's/import json/import jsonn/g' /app/tinydb-4.8.0/tinydb/storages.py

    # Create oracle script
    cat << 'EOF' > /app/oracle_pipeline.py
import sys
import pandas as pd

def main():
    if len(sys.argv) != 3:
        sys.exit(1)

    sensors_path = sys.argv[1]
    preds_path = sys.argv[2]

    sensors = pd.read_csv(sensors_path)
    preds = pd.read_csv(preds_path)

    df = pd.merge(sensors, preds, on='id', how='inner')
    df = df[abs(df['actual_value'] - df['pred_value']) < df['threshold']]
    df = df.sort_values(by='id', ascending=True)
    df = df[['id', 'actual_value', 'pred_value', 'threshold']]

    df.to_csv(sys.stdout, index=False)

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
