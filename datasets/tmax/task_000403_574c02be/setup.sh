#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/notes.csv
id,text
101,"Sample heated to 400K, showed luminescence"
102,"Sample cooled, no reaction"
103,"Exploded upon contact with water"
104,"Stable at room temperature"
105,"Degraded rapidly in UV light"
EOF

    cat << 'EOF' > /home/user/data/metrics.csv
id,quality_label
101,1
102,0
103,0
104,1
EOF

    cat << 'EOF' > /home/user/clean_pipeline.py
import pandas as pd

notes = pd.read_csv('/home/user/data/notes.csv')
metrics = pd.read_csv('/home/user/data/metrics.csv')

df = notes.merge(metrics, on='id', how='left')
df.to_csv('/home/user/data/cleaned_data.csv', index=False)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
