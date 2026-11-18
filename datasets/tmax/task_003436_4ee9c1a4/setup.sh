#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/create_data.py
import pandas as pd
import os

os.makedirs('/home/user', exist_ok=True)

data = {
    'id': range(1, 11),
    'sqft': [1500, 1600, 2000, 1200, 1800, 2200, 1300, 2100, 1900, 2500],
    'bedrooms': [3, 3, 4, 2, 3, 4, 2, 4, 3, 5],
    'zip_code': ['90210', '90210', '90210', '10001', '10001', '30301', '30301', '30301', '30301', '99999'],
    'price': [1000000, 1100000, 1200000, 800000, 850000, 500000, 450000, 550000, 520000, 300000]
}

df = pd.DataFrame(data)
df.to_csv('/home/user/raw_housing.csv', index=False)
EOF

    python3 /tmp/create_data.py

    chmod -R 777 /home/user
