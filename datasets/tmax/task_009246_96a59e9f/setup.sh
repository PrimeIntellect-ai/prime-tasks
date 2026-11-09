#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy scikit-learn

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data
mkdir -p /home/user/scripts
mkdir -p /home/user/experiments

cat << 'EOF' > /home/user/scripts/setup_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
n = 1000
ids = np.arange(n)
f1 = np.random.randn(n)
targets = np.random.randint(0, 2, n)
df1 = pd.DataFrame({'id': ids, 'feature1': f1, 'target': targets})
df1.to_csv('/home/user/data/features.csv', index=False)

cat_ids = np.random.choice([1, 2, 3], int(n*0.8))
# 80% have categories
selected_ids = np.random.choice(ids, int(n*0.8), replace=False)
df2 = pd.DataFrame({'id': selected_ids, 'category_id': cat_ids})
df2.to_csv('/home/user/data/categories.csv', index=False)
EOF

python3 /home/user/scripts/setup_data.py

cat << 'EOF' > /home/user/scripts/pipeline.py
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import GridSearchCV
import json
import os

def load_and_prep():
    df1 = pd.read_csv('/home/user/data/features.csv')
    df2 = pd.read_csv('/home/user/data/categories.csv')

    # Left join causes missing category_id to become NaN, casting column to float
    df = df1.merge(df2, on='id', how='left')

    # TODO: Fill missing category_id with -1 and cast to int

    return df

def run_experiment():
    df = load_and_prep()
    X = df[['feature1', 'category_id']]
    y = df['target']

    # TODO: 5-fold CV Grid Search with RandomForestClassifier
    # param_grid = {'n_estimators': [10, 50], 'max_depth': [3, 5]}
    # random_state = 42

    # TODO: Save results to /home/user/experiments/results.json
    # TODO: Save best params to /home/user/experiments/best_params.json

if __name__ == "__main__":
    run_experiment()
EOF

chmod -R 777 /home/user
