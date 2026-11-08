#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)

data = {
    'user_id': [1, 2, 3, 1, 4],
    'age': [25, 34, 45, 25, 29],
    'q1_response': ['Great product!', '  Needs work... ', np.nan, 'Great product!', 'Awesome!!!'],
    'q2_response': ['Too expensive.', np.nan, 'Okay.', 'Too expensive.', 'Loved it!'],
    'q3_response': [np.nan, 'No comment', 'Very bad-experience', np.nan, 'Yes.']
}

df = pd.DataFrame(data)
df.to_csv('/home/user/raw_surveys.csv', index=False)
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
