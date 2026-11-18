#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn joblib

    mkdir -p /home/user/data_project
    cd /home/user/data_project

    cat << 'EOF' > generate_data.py
import pandas as pd
from sklearn.datasets import make_classification

X, y = make_classification(n_samples=2000, n_features=60, n_informative=15, random_state=123)
df = pd.DataFrame(X, columns=[f"feature_{i}" for i in range(60)])
df["target"] = y
df.to_csv("dataset.csv", index=False)
EOF

    cat << 'EOF' > train_model.py
import pandas as pd
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score

# Load data
df = pd.read_csv("dataset.csv")
X = df.drop("target", axis=1)
y = df["target"]

# --- DATA LEAKAGE HERE ---
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

pca = PCA(n_components=10, random_state=42)
X_pca = pca.fit_transform(X_scaled)
# -------------------------

X_train, X_test, y_train, y_test = train_test_split(X_pca, y, test_size=0.2, random_state=42)

model = LogisticRegression(random_state=42)
model.fit(X_train, y_train)

preds = model.predict(X_test)
print("Accuracy:", accuracy_score(y_test, preds))
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
