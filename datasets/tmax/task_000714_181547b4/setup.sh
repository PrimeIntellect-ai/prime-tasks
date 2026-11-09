#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy requests

    mkdir -p /home/user

    cat << 'EOF' > /home/user/create_data.py
import pandas as pd
import numpy as np

data = {
    "timestamp": pd.date_range(start="2023-01-01", periods=10, freq="h"),
    "temperature": [20.0, np.nan, 21.0, 22.5, 22.0, np.nan, 23.0, 23.5, 24.0, 25.0],
    "humidity": [45.0, 50.0, 55.0, -10.0, 60.0, 65.0, 70.0, 150.0, 80.0, 85.0]
}
df = pd.DataFrame(data)
df.to_csv("/home/user/raw_data.csv", index=False)
EOF

    python3 /home/user/create_data.py
    rm /home/user/create_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
