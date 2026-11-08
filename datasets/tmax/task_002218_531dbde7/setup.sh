#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest pandas

    mkdir -p /app/text_feature_toolkit/text_feature_toolkit

    cat << 'EOF' > /app/text_feature_toolkit/setup.py
from setuptools import setup, find_packages

setup(
    name="text_feature_toolkit",
    version="1.0.0",
    packages=find_packages(),
    install_requires=["pandas"],
)
EOF

    cat << 'EOF' > /app/text_feature_toolkit/text_feature_toolkit/__init__.py
from .processor import build_features
EOF

    cat << 'EOF' > /app/text_feature_toolkit/text_feature_toolkit/processor.py
import pandas as pd

def build_features(df, meta_csv="/app/reference_meta.csv"):
    meta_df = pd.read_csv(meta_csv)
    # The bug is here
    merged_df = pd.merge(df, meta_df, on="meta_id", how="left")

    if merged_df.empty:
        return []

    features = []
    for _, row in merged_df.iterrows():
        # dummy tokenization
        text = str(row['text'])
        tokens = [len(w) for w in text.split()]
        meta_token = int(row['meta_token'])
        features.extend(tokens + [meta_token])

    return features
EOF

    cd /app/text_feature_toolkit && pip3 install -e .

    echo "meta_id,meta_token" > /app/reference_meta.csv
    for i in $(seq 1 250); do
        echo "$i,$((i*10))" >> /app/reference_meta.csv
    done

    cat << 'EOF' > /app/oracle_processor
#!/usr/bin/env python3
import sys
import json
import pandas as pd

def process():
    line = sys.stdin.readline().strip()
    if not line:
        return
    data = json.loads(line)

    meta_df = pd.read_csv("/app/reference_meta.csv")
    df = pd.DataFrame([data])
    merged = pd.merge(df, meta_df, on="meta_id", how="inner")

    if merged.empty:
        print("INVALID")
        return

    features = []
    for _, row in merged.iterrows():
        text = str(row['text'])
        tokens = [len(w) for w in text.split()]
        meta_token = int(row['meta_token'])
        features.extend(tokens + [meta_token])

    print(",".join(map(str, features)))

if __name__ == "__main__":
    process()
EOF
    chmod +x /app/oracle_processor

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
