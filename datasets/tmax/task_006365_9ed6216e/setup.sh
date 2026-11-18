#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np

# Create temperature.csv (UTF-16 with embedded newlines)
temp_data = {
    'time_str': [
        '2023/10/01 00:00:00',
        '2023/10/01 00:15:00',
        '2023/10/01 00:43:00',
        '2023/10/01 01:22:00',
        '2023/10/01 01:55:00'
    ],
    'temp_celsius': [22.0, 22.5, 23.1, 21.8, 22.2],
    'sensor_notes': [
        'Started',
        'Door opened\nslight draft',
        'Heater on',
        'Window open\n\nchilly',
        'Normal'
    ]
}
df_temp = pd.DataFrame(temp_data)
df_temp.to_csv('/home/user/temperature.csv', index=False, encoding='utf-16')

# Create humidity.csv (UTF-8)
hum_data = {
    'timestamp': [
        '2023-10-01T00:00:00Z',
        '2023-10-01T00:33:00Z',
        '2023-10-01T01:15:00Z',
        '2023-10-01T01:45:00Z'
    ],
    'humidity_percent': [40.0, 42.5, 45.1, 44.0]
}
df_hum = pd.DataFrame(hum_data)
df_hum.to_csv('/home/user/humidity.csv', index=False, encoding='utf-8')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
