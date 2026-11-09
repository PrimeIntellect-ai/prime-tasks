#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest pandas numpy matplotlib

    mkdir -p /home/user

    python3 -c "
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user', exist_ok=True)

# Generate dataset with large offset to cause catastrophic cancellation in naive formulas
np.random.seed(42)
n = 1000
offset = 1e9

A = np.random.randn(n) + offset
B = A + np.random.randn(n) * 0.5 - offset + offset # B is highly correlated with A
C = np.random.randn(n) * 2 + offset # C is independent

df = pd.DataFrame({'Sensor_A': A, 'Sensor_B': B, 'Sensor_C': C})
df.to_csv('/home/user/sensordata.csv', index=False)

# Create the broken script
broken_script = '''import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

def naive_cov(x, y):
    n = len(x)
    sum_x = sum(x)
    sum_y = sum(y)
    sum_xy = sum(x.iloc[i]*y.iloc[i] for i in range(n))
    return (sum_xy - (sum_x*sum_y)/n) / (n-1)

def naive_var(x):
    return naive_cov(x, x)

def naive_corr(x, y):
    var_x = naive_var(x)
    var_y = naive_var(y)
    if var_x <= 0 or var_y <= 0: return 0
    return naive_cov(x, y) / np.sqrt(var_x * var_y)

df = pd.read_csv('/home/user/sensordata.csv')
cols = df.columns

corr_matrix = pd.DataFrame(index=cols, columns=cols, dtype=float)
cov_matrix = pd.DataFrame(index=cols, columns=cols, dtype=float)

for c1 in cols:
    for c2 in cols:
        corr_matrix.loc[c1, c2] = naive_corr(df[c1], df[c2])
        cov_matrix.loc[c1, c2] = naive_cov(df[c1], df[c2])

corr_matrix.round(4).to_csv('/home/user/correlation.csv')
cov_matrix.round(4).to_csv('/home/user/covariance.csv')

plt.imshow(corr_matrix.values)
plt.savefig('/home/user/heatmap.png')
'''

with open('/home/user/analyze.py', 'w') as f:
    f.write(broken_script)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
