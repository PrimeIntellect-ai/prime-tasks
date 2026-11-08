#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np

np.random.seed(42)
n = 1000
temp = np.random.normal(20, 5, n)
pressure = temp * 2.5 + np.random.normal(1013, 10, n)
humidity = np.random.uniform(30, 90, n)
vibration = 0.5 * temp - 0.2 * pressure + 0.1 * humidity + np.random.normal(0, 2, n)

df = pd.DataFrame({
    'time': range(n),
    'temp': temp,
    'pressure': pressure,
    'humidity': humidity,
    'vibration': vibration
})
df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
