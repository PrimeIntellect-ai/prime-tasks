#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    mkdir -p /home/user/mlops_pipeline/artifacts

    cat << 'EOF' > /home/user/mlops_pipeline/raw_data.csv
doc_id,text,author_id
1,hello world,10
2,data science is fun,
3,hello machine learning,20
4,machine learning is fun,
5,reproducible pipelines are great,30
6,tokenization and dataset preparation,
7,dimensionality reduction is a primitive,40
EOF

    cat << 'EOF' > /home/user/mlops_pipeline/build_features.py
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.decomposition import TruncatedSVD
import os

os.makedirs('/home/user/mlops_pipeline/artifacts', exist_ok=True)

# Load data
df = pd.read_csv('/home/user/mlops_pipeline/raw_data.csv')

# TF-IDF Tokenization
vectorizer = TfidfVectorizer()
X = vectorizer.fit_transform(df['text'])

# Dimensionality Reduction
svd = TruncatedSVD(n_components=2)
svd_features = svd.fit_transform(X)

df['svd_0'] = svd_features[:, 0]
df['svd_1'] = svd_features[:, 1]

# Save artifacts
df.to_csv('/home/user/mlops_pipeline/artifacts/features.csv', index=False)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
