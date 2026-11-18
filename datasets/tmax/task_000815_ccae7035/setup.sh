#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc make
    pip3 install pytest numpy scikit-learn matplotlib

    mkdir -p /app
    cd /app

    cat << 'EOF' > setup.py
import numpy as np
from sklearn.datasets import make_classification
from sklearn.model_selection import train_test_split
import matplotlib.pyplot as plt

# Generate synthetic data
X, y = make_classification(n_samples=200, n_features=4, n_informative=4, n_redundant=0, n_classes=3, random_state=42)
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.25, random_state=42)

np.savetxt('/app/train.csv', np.column_stack((X_train, y_train)), delimiter=',', fmt='%.4f,%.4f,%.4f,%.4f,%d')
np.savetxt('/app/test.csv', X_test, delimiter=',', fmt='%.4f,%.4f,%.4f,%.4f')
np.savetxt('/app/test_labels.csv', y_test, delimiter=',', fmt='%d')

# Create configuration image
fig, ax = plt.subplots(figsize=(6, 4))
ax.text(0.5, 0.5, "PIPELINE CONFIG\nMODEL: KNN\nK=5\nDIST: EUCLIDEAN", fontsize=20, ha='center', va='center')
ax.axis('off')
fig.savefig('/app/config.png', bbox_inches='tight', dpi=150)
EOF

    python3 setup.py
    rm setup.py
    chmod 644 /app/train.csv /app/test.csv /app/config.png
    chmod 600 /app/test_labels.csv

    cat << 'EOF' > /app/verify.py
import numpy as np
import sys

def verify():
    try:
        expected = np.loadtxt('/app/test_labels.csv', dtype=int)
    except Exception as e:
        print(f"Error loading truth: {e}")
        return 0.0

    try:
        actual = np.loadtxt('/home/user/predictions.csv', dtype=int)
    except Exception as e:
        print(f"Error loading predictions: {e}")
        return 0.0

    if len(expected) != len(actual):
        print(f"Length mismatch: expected {len(expected)}, got {len(actual)}")
        return 0.0

    accuracy = np.mean(expected == actual)
    print(accuracy)
    return accuracy

if __name__ == "__main__":
    verify()
EOF
    chmod 644 /app/verify.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
