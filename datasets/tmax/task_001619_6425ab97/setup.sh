#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scikit-learn

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ml_project
    cd /home/user/ml_project

    cat << 'EOF' > generate_data.py
import numpy as np
import pandas as pd
from sklearn.datasets import make_regression

X, y = make_regression(n_samples=500, n_features=10, n_informative=5, random_state=42, noise=1.5)
# Introduce correlation to make PCA useful
transformation = np.random.RandomState(42).rand(10, 10)
X = np.dot(X, transformation)

df = pd.DataFrame(X, columns=[f"feat_{i}" for i in range(10)])
df['target'] = y
df.to_csv("data.csv", index=False)
EOF

    python3 generate_data.py
    rm generate_data.py

    cat << 'EOF' > pipeline.py
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_squared_error
import json

def custom_pca(X, n_components=3):
    """Custom PCA implementation."""
    mean = np.mean(X, axis=0)
    X_centered = X - mean

    # Covariance matrix
    cov_matrix = np.cov(X_centered, rowvar=False)

    # Eigen decomposition
    eigenvalues, eigenvectors = np.linalg.eigh(cov_matrix)

    # Sort by eigenvalues descending
    sorted_indices = np.argsort(eigenvalues)[::-1]
    top_indices = sorted_indices[:n_components]

    top_eigenvectors = eigenvectors[:, top_indices]

    # Transform data
    X_pca = np.dot(X_centered, top_eigenvectors)

    return X_pca

def main():
    # Load data
    df = pd.read_csv("data.csv")
    X = df.drop(columns=["target"]).values
    y = df["target"].values

    # BUG: Data leakage! PCA applied to entire dataset before split
    X_pca = custom_pca(X, n_components=3)

    # Train/test split
    X_train, X_test, y_train, y_test = train_test_split(X_pca, y, test_size=0.2, random_state=42, shuffle=False)

    # Model training
    model = LinearRegression()
    model.fit(X_train, y_train)

    # Predictions
    y_pred_train = model.predict(X_train)
    y_pred_test = model.predict(X_test)

    train_mse = mean_squared_error(y_train, y_pred_train)
    test_mse = mean_squared_error(y_test, y_pred_test)

    metrics = {
        "train_mse": round(train_mse, 4),
        "test_mse": round(test_mse, 4)
    }

    with open("metrics.json", "w") as f:
        json.dump(metrics, f, indent=4)

if __name__ == "__main__":
    main()
EOF

    chmod -R 777 /home/user
