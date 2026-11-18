#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest pandas pyarrow scikit-learn matplotlib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import pandas as pd
import numpy as np
import pyarrow as pa
import pyarrow.parquet as pq
from sklearn.datasets import make_classification

# Generate reproducible synthetic data
X, _ = make_classification(n_samples=5000, n_features=50, n_informative=15, 
                           n_redundant=10, random_state=123)
df = pd.DataFrame(X, columns=[f"feat_{i}" for i in range(50)])
df.to_parquet('/home/user/data.parquet')

# Generate the initial broken script
broken_script = """import pandas as pd
import matplotlib.pyplot as plt
from sklearn.decomposition import PCA
import json

def run_diagnostics():
    # 1. Load data
    df = pd.read_parquet('/home/user/data.parquet')

    # 2. Bootstrap sampling (Currently missing!)
    # TODO: Take a bootstrap sample of 1000 rows with replacement (random_state=42)
    sample_df = df 

    # 3. Dimensionality Reduction
    # TODO: Find minimum n_components that explains >= 85% of variance
    pca = PCA(n_components=2)
    pca.fit(sample_df)

    # 4. Plotting (Failing in headless environment!)
    plt.figure()
    plt.plot(pca.explained_variance_ratio_.cumsum(), marker='o')
    plt.title('PCA Explained Variance')
    plt.show() 

    # 5. Tracking (Currently missing!)
    # TODO: Save the optimal n_components and its cumulative variance to /home/user/tracking.json
    # Format: {"n_components": int, "variance_explained": float}

if __name__ == "__main__":
    run_diagnostics()
"""
with open('/home/user/etl_diagnostic.py', 'w') as f:
    f.write(broken_script)
EOF
    python3 /tmp/setup_data.py

    chmod -R 777 /home/user
