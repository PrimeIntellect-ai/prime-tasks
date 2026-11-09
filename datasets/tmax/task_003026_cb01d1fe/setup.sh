#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas scipy matplotlib

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data

cat << 'EOF' > /home/user/data/log1.csv
timestamp,server,response_time
2023-01-01T10:00:00,Server_A,100
2023-01-01T10:01:00,Server_A,102
2023-01-01T10:02:00,Server_A,101
2023-01-01T10:03:00,Server_A,105
2023-01-01T10:04:00,Server_A,100
EOF

cat << 'EOF' > /home/user/data/log2.csv
timestamp,server,response_time
2023-01-02T10:00:00,Server_B,110
2023-01-02T10:01:00,Server_B,112
2023-01-02T10:02:00,Server_B,invalid_data
2023-01-02T10:03:00,Server_B,115
2023-01-02T10:04:00,Server_B,111
2023-01-02T10:05:00,Server_B,109
EOF

cat << 'EOF' > /home/user/analytics.py
import pandas as pd
import glob
import scipy.stats as stats
import matplotlib
matplotlib.use('TkAgg') # Causes crash in headless env
import matplotlib.pyplot as plt
import json

files = glob.glob('/home/user/data/*.csv')
dfs = []
for f in files:
    df = pd.read_csv(f)
    dfs.append(df)

data = pd.concat(dfs)

# The data schema is not enforced properly here.
# Missing: data['response_time'] = pd.to_numeric(data['response_time'], errors='coerce')
# Missing: data = data.dropna(subset=['response_time'])

server_a = data[data['server'] == 'Server_A']['response_time']
server_b = data[data['server'] == 'Server_B']['response_time']

t_stat, p_val = stats.ttest_ind(server_a, server_b)

with open('/home/user/results.json', 'w') as f:
    json.dump({'t_stat': t_stat, 'p_value': p_val}, f)

plt.hist(server_a, alpha=0.5, label='A')
plt.hist(server_b, alpha=0.5, label='B')
plt.legend()
plt.savefig('/home/user/report.png')
EOF

chown -R user:user /home/user
chmod -R 777 /home/user
