#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy matplotlib seaborn scikit-learn

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user/ml_pipeline', exist_ok=True)

# Generate raw_data.csv
np.random.seed(10)
n_samples = 1000
f1 = np.random.normal(0, 1, n_samples)
f2 = f1 * 0.9 + np.random.normal(0, 0.1, n_samples) # Correlated with f1 > 0.85
f3 = np.random.normal(0, 1, n_samples)
f4 = np.random.normal(0, 1, n_samples)

# Imbalanced target
target = np.zeros(n_samples, dtype=int)
idx = np.random.choice(n_samples, 100, replace=False)
target[idx] = 1

df = pd.DataFrame({'f1': f1, 'f2': f2, 'f3': f3, 'f4': f4, 'target': target})
df.to_csv('/home/user/ml_pipeline/raw_data.csv', index=False)

# Create broken prepare_data.py
broken_script = \"\"\"import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import f1_score
from sklearn.utils import resample

def plot_correlation(df):
    plt.figure(figsize=(8, 6))
    sns.heatmap(df.corr(), annot=True, cmap='coolwarm')
    # BUG: plt.show() clears the figure before savefig can write it
    plt.show()
    plt.savefig('/home/user/ml_pipeline/correlation_plot.png')

def filter_features(df):
    # TODO: Drop features with absolute correlation > 0.85
    # Keep the first feature, drop the subsequent ones
    pass

def bootstrap_balance(df):
    # TODO: Upsample minority class to match majority class using resample
    # Use random_state=42
    pass

def train_evaluate(df):
    # Split into X and y
    X = df.drop('target', axis=1)
    y = df['target']
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

    # TODO: Train RandomForestClassifier(random_state=42)
    # TODO: Calculate F1 score and save to /home/user/ml_pipeline/metrics.txt
    pass

if __name__ == \"__main__\":
    df = pd.read_csv('/home/user/ml_pipeline/raw_data.csv')
    plot_correlation(df.drop('target', axis=1))

    df_filtered = filter_features(df)
    df_balanced = bootstrap_balance(df_filtered)

    df_balanced.to_csv('/home/user/ml_pipeline/processed_data.csv', index=False)

    train_evaluate(df_balanced)
\"\"\"

with open('/home/user/ml_pipeline/prepare_data.py', 'w') as f:
    f.write(broken_script)
"

    chmod -R 777 /home/user
