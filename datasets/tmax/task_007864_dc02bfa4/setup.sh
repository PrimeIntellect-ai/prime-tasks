#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user/data /home/user/scripts /home/user/results

    cat << 'EOF' > /home/user/scripts/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
n_samples = 100
data = {
    'id': range(1, n_samples + 1),
    'category': np.random.choice([10, 20, 30, 999], size=n_samples),
    'f1': np.random.randn(n_samples),
    'target': np.random.randint(0, 2, size=n_samples)
}
data['f2'] = data['f1'] * 0.5 + np.random.randn(n_samples) * 0.1
data['f3'] = data['f1'] * -0.3 + np.random.randn(n_samples) * 0.2
data['f4'] = np.random.randn(n_samples)
data['f5'] = data['f4'] * 0.8 + np.random.randn(n_samples) * 0.1

df = pd.DataFrame(data)
df.to_csv('/home/user/data/raw_features.csv', index=False)
EOF

    python3 /home/user/scripts/generate_data.py

    cat << 'EOF' > /home/user/scripts/preprocess.py
import pandas as pd
import numpy as np

def run_pipeline():
    df = pd.read_csv('/home/user/data/raw_features.csv')

    # Replace invalid category '999' with NaN
    df.loc[df['category'] == 999, 'category'] = np.nan

    # PCA implementation
    features = df[['f1', 'f2', 'f3', 'f4', 'f5']].values

    cov_matrix = np.cov(features, rowvar=False)
    eigenvalues, eigenvectors = np.linalg.eigh(cov_matrix)

    sorted_idx = np.argsort(eigenvalues)[::-1]
    eigenvectors = eigenvectors[:, sorted_idx]

    pca_components = features.dot(eigenvectors[:, :2])
    df['pca_1'] = pca_components[:, 0]
    df['pca_2'] = pca_components[:, 1]

    df = df[['id', 'category', 'pca_1', 'pca_2', 'target']]
    df.to_csv('/home/user/results/clean_data.csv', index=False)

if __name__ == '__main__':
    run_pipeline()
EOF

    chmod +x /home/user/scripts/preprocess.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
