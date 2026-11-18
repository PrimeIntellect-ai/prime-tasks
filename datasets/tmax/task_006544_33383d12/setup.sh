#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Install requirements to generate data (and for the agent to use)
pip3 install pandas==2.1.4 scikit-learn==1.3.2 numpy==1.26.2

mkdir -p /home/user/data/processed
mkdir -p /home/user/src

cat << 'EOF' > /home/user/requirements.txt
pandas==2.1.4
scikit-learn==1.3.2
numpy==1.26.2
EOF

cat << 'EOF' > /home/user/src/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(10)
n = 100
user_ids = np.arange(1, n + 1)
ages = np.random.normal(35, 10, n)
ages[np.random.choice(n, 10, replace=False)] = np.nan
incomes = np.random.normal(60000, 15000, n)
incomes[0] = 1000000 # Outlier
incomes[50] = 500 # Outlier
activities = np.random.uniform(1, 10, n)
activities[np.random.choice(n, 15, replace=False)] = np.nan

df = pd.DataFrame({'user_id': user_ids, 'age': ages, 'income': incomes, 'activity_score': activities})
df.to_csv('/home/user/data/raw_users.csv', index=False)
EOF

python3 /home/user/src/generate_data.py

cat << 'EOF' > /home/user/src/pipeline.py
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.impute import SimpleImputer
from sklearn.preprocessing import StandardScaler

df = pd.read_csv('/home/user/data/raw_users.csv')
features = ['age', 'income', 'activity_score']

# FAULTY: Leaking test data into the training preprocessing
imputer = SimpleImputer(strategy='mean')
df[features] = imputer.fit_transform(df[features])

scaler = StandardScaler()
df[features] = scaler.fit_transform(df[features])

# Splitting AFTER preprocessing
train, test = train_test_split(df, test_size=0.25, random_state=42, shuffle=False)

# TODO: Save train and test to /home/user/data/processed/
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
