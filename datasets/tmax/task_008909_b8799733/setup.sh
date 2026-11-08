#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest pandas numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/train.csv
id,f1,f2,f3
1,10.0,20.0,30.0
2,15.0,25.0,35.0
3,12.0,22.0,32.0
4,100.0,10.0,5.0
5,50.0,50.0,50.0
EOF

    cat << 'EOF' > /home/user/test.csv
id,f1,f2,f3
101,11.0,21.0,31.0
102,90.0,15.0,10.0
103,45.0,45.0,45.0
104,14.0,26.0,34.0
EOF

    cat << 'EOF' > /tmp/solve.py
import pandas as pd
import numpy as np

train = pd.read_csv('/home/user/train.csv')
test = pd.read_csv('/home/user/test.csv')

features = ['f1', 'f2', 'f3']
mean = train[features].mean()
std = train[features].std(ddof=1)

std[std == 0] = 1

train_std = train.copy()
train_std[features] = (train[features] - mean) / std

test_std = test.copy()
test_std[features] = (test[features] - mean) / std

out = []
for i, test_row in test_std.iterrows():
    dists = np.sqrt(((train_std[features] - test_row[features])**2).sum(axis=1))
    min_dist = dists.min()
    closest_idx = train_std[dists == min_dist]['id'].min()
    out.append((int(test_row['id']), int(closest_idx)))

with open('/home/user/closest_ground_truth.csv', 'w') as f:
    f.write('test_id,closest_train_id\n')
    for t, c in out:
        f.write(f"{t},{c}\n")
EOF

    python3 /tmp/solve.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
