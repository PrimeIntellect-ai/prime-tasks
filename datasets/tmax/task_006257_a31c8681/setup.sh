#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import pandas as pd
import numpy as np

# Generate mock data
np.random.seed(42)
X = np.random.randn(500, 5)
X[np.random.choice(500, 50), 0] = np.nan # Add NaNs to Feature_0
df = pd.DataFrame(X, columns=[f"Feature_{i}" for i in range(5)])
df["Target"] = np.random.randint(0, 2, 500)
df.to_csv("/home/user/dataset.csv", index=False)
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    cat << 'EOF' > /home/user/pipeline.py
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.impute import SimpleImputer
from sklearn.preprocessing import StandardScaler

def process_data(csv_path):
    df = pd.read_csv(csv_path)
    X = df.drop(columns=["Target"])
    y = df["Target"]

    # WARNING: Data Leakage below!
    imputer = SimpleImputer(strategy='mean')
    X_imputed = imputer.fit_transform(X)

    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X_imputed)

    # Splitting after transforming the whole dataset
    X_train, X_test, y_train, y_test = train_test_split(
        X_scaled, y, test_size=0.2, random_state=42
    )

    return X_train, X_test, y_train, y_test

if __name__ == "__main__":
    process_data("/home/user/dataset.csv")
EOF

    chmod -R 777 /home/user
