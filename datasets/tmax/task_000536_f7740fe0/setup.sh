#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn matplotlib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
data = np.random.randn(50, 5)
# Introduce some NaNs
data[5, 2] = np.nan
data[12, 4] = np.nan
data[33, 0] = np.nan

df = pd.DataFrame(data, columns=['A', 'B', 'C', 'D', 'E'])
df.to_csv('/home/user/data.csv', index=False)
EOF
    python3 /tmp/generate_data.py

    cat << 'EOF' > /home/user/etl_pipeline.py
import pandas as pd
import matplotlib.pyplot as plt
from sklearn.decomposition import PCA
from sklearn.preprocessing import StandardScaler

def main():
    # Load data
    df = pd.read_csv('/home/user/data.csv')

    # Scale data
    scaler = StandardScaler()
    scaled_data = scaler.fit_transform(df)

    # PCA
    pca = PCA(n_components=2, random_state=42)
    components = pca.fit_transform(scaled_data)

    # Plot
    plt.figure(figsize=(8, 6))
    plt.scatter(components[:, 0], components[:, 1])
    plt.title('PCA - First 2 Components')
    plt.xlabel('PC1')
    plt.ylabel('PC2')
    plt.show()

if __name__ == '__main__':
    main()
EOF

    chmod -R 777 /home/user
