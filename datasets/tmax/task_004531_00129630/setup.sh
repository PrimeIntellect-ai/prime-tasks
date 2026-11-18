#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np

data = {
    'Date': ['2023-10-01', '2023-10-02', '2023-10-03', '2023-10-04', '2023-10-05', '2023-10-06'],
    'AuthService_Timeout': [100, 200, 300, 1500, 1600, 200],
    'AuthService_MemoryLimit': [1024, 1024, 2048, 4096, 8192, 16384],
    'PaymentService_Timeout': [500, 500, 500, 500, 500, 500]
}

df = pd.DataFrame(data)
df.to_csv('/home/user/raw_configs.csv', index=False, encoding='utf-16le')
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
