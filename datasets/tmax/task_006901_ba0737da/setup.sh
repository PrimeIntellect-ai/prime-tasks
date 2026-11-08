#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn matplotlib numpy

    mkdir -p /home/user/workspace
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
from sklearn.datasets import make_classification

X, y = make_classification(n_samples=500, n_features=10, n_informative=5, random_state=42)
df = pd.DataFrame(X, columns=[f"f_{i}" for i in range(10)])
df['target'] = y
df.to_csv('/home/user/data/dataset.csv', index=False)
EOF

    python3 /home/user/setup_data.py

    cat << 'EOF' > /home/user/workspace/analyze_data.py
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score
from sklearn.decomposition import PCA

def main():
    # Load data
    df = pd.read_csv('/home/user/data/dataset.csv')
    X = df.drop('target', axis=1).values
    y = df['target'].values

    # TODO: Perform PCA to reduce X to 2 dimensions
    X_pca = X # BUG: Not reduced

    # Plotting
    plt.figure()
    # If X_pca isn't reduced, this will still scatter the first two columns, but it's not PCA
    plt.scatter(X_pca[:, 0], X_pca[:, 1], c=y)
    plt.savefig('/home/user/workspace/pca_plot.png')

    # Model training and bootstrap
    model = RandomForestClassifier(random_state=42)
    n_iterations = 100
    n_size = int(len(X) * 0.8)

    accuracies = []
    np.random.seed(42)
    for i in range(n_iterations):
        # BUG: Sampling without replacement instead of with replacement
        indices = np.random.choice(len(X), n_size, replace=False) 
        X_sample = X_pca[indices]
        y_sample = y[indices]

        # OOB evaluation
        oob_indices = list(set(range(len(X))) - set(indices))
        if len(oob_indices) == 0: continue
        X_test = X_pca[oob_indices]
        y_test = y[oob_indices]

        model.fit(X_sample, y_sample)
        preds = model.predict(X_test)
        acc = accuracy_score(y_test, preds)
        accuracies.append(acc)

    # Calculate 95% CI
    # BUG: incorrect percentiles
    lower = np.percentile(accuracies, 10)
    upper = np.percentile(accuracies, 90)

    with open('/home/user/workspace/metrics.txt', 'w') as f:
        f.write(f"Lower: {lower:.4f}\nUpper: {upper:.4f}\n")

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
