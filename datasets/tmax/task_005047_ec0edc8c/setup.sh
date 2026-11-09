#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak curl
pip3 install pytest pandas numpy scikit-learn

mkdir -p /app

# Generate customers.csv
cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
n_users = 100
uids = np.arange(1, n_users + 1)
feat1 = np.random.uniform(0, 10, n_users)
feat2 = np.random.uniform(0, 10, n_users)
feat3 = np.random.uniform(0, 10, n_users)

spend = 2.5 * feat1 - 1.2 * feat2 + 0.5 * feat3 + np.random.normal(0, 2, n_users)

df = pd.DataFrame({
    'uid': uids,
    'feat1': feat1,
    'feat2': feat2,
    'feat3': feat3,
    'spend': spend
})
df.to_csv('/app/customers.csv', index=False)
EOF

python3 /tmp/generate_data.py

# Generate instructions.wav using espeak
espeak -w /app/instructions.wav "Hello. I need you to build an HTTP server listening on port 8123. The service must expose two GET endpoints. First, slash similar query parameter uid. This must return a JSON array of the top 3 most similar user IDs to the requested uid, based on cosine similarity of their three feature columns: feat1, feat2, and feat3. Exclude the requested uid itself from the results. Second, slash predict query parameter uid. You must train a Ridge regression model to predict the 'spend' column using feat1, feat2, and feat3 as predictors. Use 5-fold cross validation to select the best alpha from the list: 0.1, 1.0, and 10.0. Once trained on the entire dataset with the best alpha, return the predicted spend for the requested uid as a single JSON float. The data is in slash app slash customers dot csv."

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
