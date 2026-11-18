#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest pandas numpy scikit-learn

    mkdir -p /home/user/mlops

    cat << 'EOF' > /home/user/mlops/setup.py
import pandas as pd
import numpy as np

np.random.seed(42)

# Generate runs.csv
n_runs = 100
run_ids = [f"run_{i}" for i in range(n_runs)]
lrs = np.random.uniform(0.0001, 0.1, n_runs)
batch_sizes = np.random.choice([16, 32, 64, 128], n_runs)
latencies = np.random.uniform(10, 200, n_runs)

# True underlying function for accuracy
accuracies = 0.95 - (latencies / 1000) - (lrs * 0.5) + np.random.normal(0, 0.01, n_runs)

# Introduce outliers in latency
latencies[5] = 1500
latencies[12] = -50
latencies[45] = 1200

# Introduce missing values in accuracy (after outliers are set, to ensure deterministic mean)
accuracies[10] = np.nan
accuracies[25] = np.nan
accuracies[88] = np.nan

df_runs = pd.DataFrame({
    'run_id': run_ids,
    'learning_rate': lrs,
    'batch_size': batch_sizes,
    'latency_ms': latencies,
    'accuracy': accuracies
})
df_runs.to_csv('/home/user/mlops/runs.csv', index=False)

# Generate candidates.csv
n_cands = 20
cand_ids = [f"cand_{i}" for i in range(n_cands)]
cand_lrs = np.random.uniform(0.0001, 0.1, n_cands)
cand_batch_sizes = np.random.choice([16, 32, 64, 128], n_cands)
cand_latencies = np.random.uniform(20, 100, n_cands)

# Ensure at least a few are <= 50 ms
cand_latencies[2] = 30
cand_latencies[7] = 45
cand_latencies[15] = 25

df_cands = pd.DataFrame({
    'run_id': cand_ids,
    'learning_rate': cand_lrs,
    'batch_size': cand_batch_sizes,
    'latency_ms': cand_latencies
})
df_cands.to_csv('/home/user/mlops/candidates.csv', index=False)
EOF

    python3 /home/user/mlops/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
