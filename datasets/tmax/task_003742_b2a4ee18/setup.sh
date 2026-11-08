#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data

cat << 'EOF' > /home/user/data/raw.csv
sample_id,f1,f2,f3,batch_id
S1,1.0,2.0,3.0,1
S2,4.0,5.0,6.0,
S3,7.0,8.0,9.0,2
EOF

cat << 'EOF' > /home/user/data/meta.json
{"1": 0.5, "2": 2.0, "999": 1.0}
EOF

cat << 'EOF' > /home/user/data/weights.csv
0,1,0
0,0,1
1,0,0
EOF

cat << 'EOF' > /home/user/etl_pipeline.py
import pandas as pd
import numpy as np
import json

# Load data
df = pd.read_csv('/home/user/data/raw.csv')
with open('/home/user/data/meta.json', 'r') as f:
    meta = json.load(f)
W = pd.read_csv('/home/user/data/weights.csv', header=None).values

# Bug 1: Missing values cause batch_id to be float. astype(str) makes it '1.0' instead of '1'
df['batch_id_str'] = df['batch_id'].astype(str)
scaling_factors = df['batch_id_str'].map(meta).fillna(1.0).values

# Extract feature matrix X
X = df[['f1', 'f2', 'f3']].values

# Bug 2: Element-wise multiplication instead of matrix multiplication
Y = X * W

# Apply scaling
Y_scaled = Y * scaling_factors[:, np.newaxis]

# Save output
out_df = pd.DataFrame(Y_scaled, columns=['out1', 'out2', 'out3'])
out_df.insert(0, 'sample_id', df['sample_id'])
out_df.to_csv('/home/user/output.csv', index=False)
EOF

chmod -R 777 /home/user
