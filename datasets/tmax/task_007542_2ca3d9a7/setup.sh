#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy scikit-learn

mkdir -p /home/user/research
cd /home/user/research

cat << 'EOF' > generate_data.py
import pandas as pd
import numpy as np
from sklearn.datasets import make_regression

np.random.seed(42)
X, y = make_regression(n_samples=500, n_features=10, noise=0.5, random_state=42)
df = pd.DataFrame(X, columns=[f"feature_{i}" for i in range(10)])
df["target"] = y

# Introduce missing values to simulate real-world data
for col in df.columns[:-1]:
    mask = np.random.rand(len(df)) < 0.1
    df.loc[mask, col] = np.nan

df.to_csv("data.csv", index=False)
EOF

python3 generate_data.py
rm generate_data.py

cat << 'EOF' > train_model.py
import pandas as pd
from sklearn.impute import SimpleImputer
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import Ridge
from sklearn.model_selection import cross_val_score, KFold

df = pd.read_csv("data.csv")
X = df.drop("target", axis=1)
y = df["target"]

# DATA LEAK: Applying imputation and scaling to the whole dataset!
X_imputed = SimpleImputer(strategy='mean').fit_transform(X)
X_scaled = StandardScaler().fit_transform(X_imputed)

model = Ridge(alpha=1.0, random_state=42)
cv = KFold(n_splits=5, shuffle=True, random_state=42)
scores = cross_val_score(model, X_scaled, y, cv=cv)

print("CV Score:", scores.mean())
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
