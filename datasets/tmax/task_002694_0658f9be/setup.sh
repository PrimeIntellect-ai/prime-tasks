#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest pandas numpy scikit-learn flask fastapi uvicorn requests

    mkdir -p /app
    git clone --depth 1 -b v0.23.1 https://github.com/pyjanitor-devs/pyjanitor.git /app/pyjanitor

    # Inject the bug
    sed -i 's/df\[column_name\] = df\[column_name\].fillna(value)/if pd.api.types.is_integer_dtype(df[column_name]):\n            df[column_name] = df[column_name].astype(float)\n            df.loc[df[column_name].isna(), column_name] = np.nan\n        else:\n            df[column_name] = df[column_name].fillna(value)/g' /app/pyjanitor/janitor/functions/fill.py

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/create_data.py
import pandas as pd
import numpy as np

n_samples = 1000
np.random.seed(42)
df = pd.DataFrame({
    'feat1': np.random.randint(0, 100, n_samples),
    'feat2': np.random.randint(0, 100, n_samples),
    'feat3': np.random.randint(0, 100, n_samples),
    'target': np.random.rand(n_samples)
})
df['feat1'] = df['feat1'].astype('Int64')
df.loc[0:10, 'feat1'] = pd.NA
df.to_csv('/home/user/train_data.csv', index=False)
EOF
    python3 /tmp/create_data.py

    chmod -R 777 /home/user
