#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/data.csv
doc_id,text,category_id
1,Hello world,1
2,,2
3,Another document,
4,Final text,3
EOF

    cat << 'EOF' > /home/user/pipeline.py
import pandas as pd
import json

def process_data():
    df = pd.read_csv('/home/user/data.csv')
    df['token_length'] = df['text'].apply(lambda x: len(str(x).split()) if pd.notnull(x) else None)

    # Convert to dictionary and save to JSON
    out = df.to_dict(orient='records')
    with open('/home/user/output.json', 'w') as f:
        json.dump(out, f, indent=2)

if __name__ == "__main__":
    process_data()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
