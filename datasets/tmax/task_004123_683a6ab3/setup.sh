#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest pandas numpy scikit-learn scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import os

np.random.seed(42)

# Create data.csv
doc_ids = np.arange(1, 1001)
features = np.random.randn(1000, 5)
df_data = pd.DataFrame(features, columns=['f1', 'f2', 'f3', 'f4', 'f5'])
df_data.insert(0, 'doc_id', doc_ids)
df_data.to_csv('/home/user/data.csv', index=False)

# Create meta.csv (missing some doc_ids to trigger the NaN bug)
meta_doc_ids = np.concatenate([np.arange(1, 501), np.arange(601, 1001)])
category_ids = np.random.randint(1, 10, size=len(meta_doc_ids))
df_meta = pd.DataFrame({'doc_id': meta_doc_ids, 'category_id': category_ids})
df_meta.to_csv('/home/user/meta.csv', index=False)

# Create pipeline.py
pipeline_code = """import pandas as pd

def process_data():
    data = pd.read_csv('/home/user/data.csv')
    meta = pd.read_csv('/home/user/meta.csv')

    # Bug: This merge introduces NaNs and casts category_id to float64
    df = data.merge(meta, on='doc_id', how='left')

    df.to_csv('/home/user/processed.csv', index=False)

if __name__ == "__main__":
    process_data()
"""
with open('/home/user/pipeline.py', 'w') as f:
    f.write(pipeline_code)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
