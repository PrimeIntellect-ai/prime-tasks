#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    pip3 install scikit-learn numpy

    # Create user
    useradd -m -s /bin/bash user || true

    # Create the buggy script
    cat << 'EOF' > /home/user/train.py
import numpy as np
from sklearn.datasets import make_classification
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score

def main():
    X, y = make_classification(n_samples=200, n_features=50, n_informative=10, random_state=123)

    # Preprocessing
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)

    # Splitting
    X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.5, random_state=123)

    # Training
    clf = LogisticRegression(random_state=123)
    clf.fit(X_train, y_train)

    # Evaluation
    preds = clf.predict(X_test)
    accuracy = accuracy_score(y_test, preds)

    with open('/home/user/accuracy.txt', 'w') as f:
        f.write(f"{accuracy:.4f}\n")

if __name__ == "__main__":
    main()
EOF

    # Fix permissions
    chmod -R 777 /home/user
