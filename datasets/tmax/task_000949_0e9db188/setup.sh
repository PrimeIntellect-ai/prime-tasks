#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
import pandas as pd

os.makedirs('/home/user', exist_ok=True)

# Generate Engine A data (100 rows)
np.random.seed(10)
input_a = np.random.randint(10, 1000, 100)
latency_a = 5.0 + 0.02 * input_a + np.random.normal(0, 5, 100)
df_a = pd.DataFrame({'input_size': input_a, 'latency_ms': latency_a})
df_a.to_csv('/home/user/engine_a.csv', index=False)

# Generate Engine B data (150 rows)
np.random.seed(20)
input_b = np.random.randint(10, 1000, 150)
latency_b = 4.0 + 0.015 * input_b + np.random.normal(0, 4, 150)
df_b = pd.DataFrame({'input_size': input_b, 'latency_ms': latency_b})
df_b.to_csv('/home/user/engine_b.csv', index=False)

# Create buggy analyze.py
buggy_code = """import pandas as pd
import numpy as np
from scipy import stats
import json

df_a = pd.read_csv('/home/user/engine_a.csv')
df_b = pd.read_csv('/home/user/engine_b.csv')

# Bug 1: Covariance instead of correlation
corr_a = np.cov(df_a['input_size'], df_a['latency_ms'])[0, 1]
corr_b = np.cov(df_b['input_size'], df_b['latency_ms'])[0, 1]

# Bug 2: Irreproducible sampling
if len(df_a) > len(df_b):
    df_a = df_a.sample(len(df_b))
elif len(df_b) > len(df_a):
    df_b = df_b.sample(len(df_a))

# Bug 3: Standard t-test instead of Welch's
t_stat, p_val = stats.ttest_ind(df_a['latency_ms'], df_b['latency_ms'])

with open('/home/user/metrics.json', 'w') as f:
    json.dump({
        "correlation_A": corr_a,
        "correlation_B": corr_b,
        "t_statistic": t_stat,
        "p_value": p_val
    }, f)
"""
with open('/home/user/analyze.py', 'w') as f:
    f.write(buggy_code)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
