#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy scikit-learn

useradd -m -s /bin/bash user || true

mkdir -p /home/user/mlops_data/logs

cat << 'EOF' > /home/user/setup.py
import os
import sqlite3
import pandas as pd
import numpy as np

os.makedirs('/home/user/mlops_data/logs', exist_ok=True)

# Generate DB
conn = sqlite3.connect('/home/user/mlops_data/metadata.db')
c = conn.cursor()
c.execute('''CREATE TABLE experiments (artifact_id TEXT, model_type TEXT, training_time REAL, is_anomalous INTEGER)''')

np.random.seed(101)
artifacts = [f"art_{i:03d}" for i in range(10)]
for i, art in enumerate(artifacts):
    # Anomalous condition: high variance / high training time
    is_anom = 1 if i in [2, 7] else 0
    if i in [8, 9]:
        is_anom = None # Missing labels to predict

    c.execute("INSERT INTO experiments VALUES (?, ?, ?, ?)", 
              (art, "rf" if i%2==0 else "nn", np.random.uniform(10, 100), is_anom))

    # Generate CSVs
    n_samples = 100
    y_true = np.random.uniform(0, 10, n_samples)
    noise_level = 5.0 if is_anom == 1 else 1.0
    y_pred = y_true + np.random.normal(0, noise_level, n_samples)

    df = pd.DataFrame({'y_true': y_true, 'y_pred': y_pred})
    df.to_csv(f'/home/user/mlops_data/logs/run_{art}.csv', index=False)

conn.commit()
conn.close()
EOF

python3 /home/user/setup.py
rm /home/user/setup.py

chmod -R 777 /home/user
