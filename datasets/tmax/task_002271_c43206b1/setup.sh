#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils
    pip3 install pytest pandas scikit-learn numpy pyinstaller

    useradd -m -s /bin/bash user || true
    mkdir -p /app

    # Generate data
    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np
from sklearn.datasets import make_classification

X, y = make_classification(n_samples=1000, n_features=50, n_informative=15, n_redundant=10, random_state=42)

rng = np.random.default_rng(42)
for _ in range(500):
    i = rng.integers(0, 1000)
    j = rng.integers(0, 50)
    X[i, j] = np.nan

df = pd.DataFrame(X)
df.to_csv('/home/user/raw_data.csv', index=False, header=False)
pd.Series(y).to_csv('/app/hidden_labels.csv', index=False, header=False)
EOF

    python3 /tmp/generate_data.py

    # Create the scoring binary
    cat << 'EOF' > /tmp/score_features.py
import sys
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import cross_val_score

def main():
    if len(sys.argv) < 2:
        print("Usage: score_features <features.csv>")
        sys.exit(1)
    try:
        X = pd.read_csv(sys.argv[1], header=None).values
        y = pd.read_csv('/app/hidden_labels.csv', header=None).values.ravel()
    except Exception as e:
        print(f"Error reading files: {e}")
        sys.exit(1)
    if X.shape != (1000, 10):
        print(f"Expected shape (1000, 10), got {X.shape}")
        sys.exit(1)
    model = LogisticRegression(random_state=42)
    scores = cross_val_score(model, X, y, cv=5)
    print(scores.mean())

if __name__ == '__main__':
    main()
EOF

    cd /tmp
    pyinstaller --onefile --distpath /app score_features.py
    chmod +x /app/score_features
    strip /app/score_features || true

    # Cleanup
    rm -rf /tmp/generate_data.py /tmp/score_features.py /tmp/build /tmp/score_features.spec

    chmod -R 777 /home/user
