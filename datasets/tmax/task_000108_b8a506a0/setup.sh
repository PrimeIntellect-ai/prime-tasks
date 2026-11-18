#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scikit-learn numpy scipy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/model_pipeline.py
import json
from sklearn.datasets import make_classification
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, roc_auc_score

def main():
    # 1. Generate Data
    X, y = make_classification(n_samples=1000, n_features=20, n_informative=15, random_state=42)

    # 2. Split Data
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

    # 3. Scale Features
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.fit_transform(X_test) # BUG: Should be transform()

    # 4. Dimensionality Reduction
    pca = PCA(n_components=10, random_state=42)
    X_train_pca = pca.fit_transform(X_train_scaled)
    X_test_pca = pca.fit_transform(X_test_scaled) # BUG: Should be transform()

    # 5. Train Model
    clf = LogisticRegression(random_state=42)
    clf.fit(X_train_pca, y_train)

    # 6. Evaluate Model
    y_pred = clf.predict(X_test_pca)
    y_proba = clf.predict_proba(X_test_pca)[:, 1]

    acc = accuracy_score(y_test, y_pred)
    roc = roc_auc_score(y_test, y_proba)

    print(f"Accuracy: {acc}")
    print(f"ROC AUC: {roc}")

if __name__ == "__main__":
    main()
EOF

    chmod -R 777 /home/user
