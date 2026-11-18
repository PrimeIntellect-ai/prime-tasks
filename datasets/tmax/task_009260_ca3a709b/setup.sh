#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas pymc mlflow

    mkdir -p /home/user/datasets
    cat << 'EOF' > /home/user/datasets/batch1.csv
id,machine
1,A
2,B
3,A
4,C
5,B
EOF

    cat << 'EOF' > /home/user/datasets/batch2.csv
id,defect_count
1,3
2,1
4,0
5,2
EOF

    cat << 'EOF' > /home/user/preprocess.py
import pandas as pd

b1 = pd.read_csv('/home/user/datasets/batch1.csv')
b2 = pd.read_csv('/home/user/datasets/batch2.csv')

# This left merge introduces NaNs, causing defect_count to become float
df = pd.merge(b1, b2, on='id', how='left')

# Save to CSV
df.to_csv('/home/user/clean_data.csv', index=False)
EOF

    cat << 'EOF' > /home/user/model.py
import pandas as pd
import pymc as pm
import mlflow

df = pd.read_csv('/home/user/clean_data.csv')

if not pd.api.types.is_integer_dtype(df['defect_count']):
    raise ValueError("defect_count must be integer for Poisson modeling!")

mlflow.set_experiment("Defect_Analysis")
with mlflow.start_run() as run:
    with pm.Model() as model:
        lam = pm.Exponential('lam', 1.0)
        y = pm.Poisson('y', mu=lam, observed=df['defect_count'].values)
        idata = pm.sample(1000, tune=1000, random_seed=42, return_inferencedata=True, progressbar=False)

    posterior_mean = idata.posterior['lam'].mean().item()
    mlflow.log_metric("posterior_mean_lam", posterior_mean)

    with open('/home/user/run_id.txt', 'w') as f:
        f.write(run.info.run_id)
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
