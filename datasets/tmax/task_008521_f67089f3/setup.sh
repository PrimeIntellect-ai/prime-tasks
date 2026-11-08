#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pyarrow numpy scikit-learn

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/generate_data.py
import pandas as pd
import numpy as np
np.random.seed(42)
n = 5000
df = pd.DataFrame({
    'user_id': np.random.randint(1000000000000000, 9000000000000000, n),
    'feature_1': np.random.randn(n),
    'feature_2': np.random.rand(n) * 100,
    'target': np.random.randint(0, 2, n)
})
# Introduce some negatives to trigger cleaning
df.loc[np.random.choice(n, 500, replace=False), 'feature_1'] = -1.5
df.to_parquet('/home/user/data/dataset.parquet', index=False)
EOF

    python3 /home/user/generate_data.py

    cat << 'EOF' > /home/user/pipeline.py
import pandas as pd
import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score
import json

def load_data():
    return pd.read_parquet('/home/user/data/dataset.parquet')

def clean_data(df):
    df = df.copy()
    # Bug: Replacing with np.nan silently casts large integers to float64, losing precision
    df.loc[df['feature_1'] < -1.0, 'user_id'] = np.nan
    return df

def train_and_evaluate(df):
    X = df[['user_id', 'feature_1', 'feature_2']]
    y = df['target']

    # TODO: Replace with GridSearchCV
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
    model = HistGradientBoostingClassifier(random_state=42)
    model.fit(X_train, y_train)
    preds = model.predict(X_test)
    score = accuracy_score(y_test, preds)
    print(f"Score: {score}")

if __name__ == "__main__":
    df = load_data()
    cleaned_df = clean_data(df)
    train_and_evaluate(cleaned_df)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
