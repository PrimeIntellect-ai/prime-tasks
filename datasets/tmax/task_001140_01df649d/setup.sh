#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy

mkdir -p /home/user
cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np

np.random.seed(42)

# Generate exp_alpha.csv
# high positive correlation
x_alpha = np.random.normal(10, 2, 105)
y_alpha = 3 * x_alpha + np.random.normal(0, 1, 105)
df_alpha = pd.DataFrame({'trial_id': range(105), 'signal_x': x_alpha, 'signal_y': y_alpha})
df_alpha.loc[5, 'signal_x'] = np.nan
df_alpha.loc[10:12, 'signal_y'] = np.nan
df_alpha.to_csv('/home/user/exp_alpha.csv', index=False)

# Generate exp_beta.csv
# moderate negative correlation
x_beta = np.random.normal(5, 3, 90)
y_beta = -1.5 * x_beta + np.random.normal(0, 5, 90)
df_beta = pd.DataFrame({'trial_id': range(90), 'signal_x': x_beta, 'signal_y': y_beta})
df_beta.loc[80:85, 'signal_y'] = np.nan
df_beta.to_csv('/home/user/exp_beta.csv', index=False)
EOF

python3 /home/user/setup_data.py
rm /home/user/setup_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
