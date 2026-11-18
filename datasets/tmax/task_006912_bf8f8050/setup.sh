#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_data.py
import os
import pandas as pd
import numpy as np

os.makedirs('/home/user', exist_ok=True)

data = [
    [1, 'Paris\u0301', '2023-01-01', '5.0'],
    [1, 'Paris\u0301', '2023-01-01', '5.0'],
    [1, 'París', '2023-01-02', ''],
    [1, ' Pari\u0301s ', '2023-01-03', '9.0'],
    [1, 'París', '2023-01-04', ''],
    [2, 'München', '2023-01-01', ''],
    [2, 'Mu\u0308nchen', '2023-01-02', '-1.0'],
    [2, 'München', '2023-01-03', '-3.0'],
    [2, 'München', '2023-01-05', '-7.0'],
    [2, 'Mu\u0308nchen', '2023-01-04', ''],
]

data[-1], data[-2] = data[-2], data[-1]

df = pd.DataFrame(data, columns=['station_id', 'station_name', 'date', 'temperature'])
df.to_csv('/home/user/weather_data.csv', index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
