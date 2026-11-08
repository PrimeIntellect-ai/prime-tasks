#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/data.csv
sample_id,category_id,value
1,10,0.5
2,20,0.8
3,30,1.2
4,40,0.3
5,50,0.9
EOF

    cat << 'EOF' > /home/user/mapping.json
{"10": 1, "20": 2, "30": 3}
EOF

    cat << 'EOF' > /home/user/pipeline.py
import pandas as pd
import json

def run_pipeline():
    df = pd.read_csv('/home/user/data.csv')
    with open('/home/user/mapping.json', 'r') as f:
        mapping = json.load(f)

    # convert json keys to int for mapping
    mapping = {int(k): v for k, v in mapping.items()}

    df['category_id'] = df['category_id'].map(mapping)
    df['category_id'] = df['category_id'].fillna(-1)

    # Save features
    df.to_csv('/home/user/features.csv', index=False)

if __name__ == '__main__':
    run_pipeline()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
