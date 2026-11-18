#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scikit-learn

    mkdir -p /home/user

    cat << 'EOF' > /home/user/experiment.py
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.neighbors import KNeighborsClassifier
from sklearn.metrics import accuracy_score

# Generate synthetic dataset with a distribution shift in the latter part
np.random.seed(42)
X = np.random.randn(200, 5)
X[150:] += 50  # Outliers/Shift in the test set portion
y = np.random.randint(0, 2, 200)

# BUG: Data Leakage! Fitting the scaler on the entire dataset
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

# Splitting after scaling leaks test statistics into training data
X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.25, random_state=42, shuffle=False)

model = KNeighborsClassifier(n_neighbors=3)
model.fit(X_train, y_train)
preds = model.predict(X_test)

print(f"{accuracy_score(y_test, preds):.4f}")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
