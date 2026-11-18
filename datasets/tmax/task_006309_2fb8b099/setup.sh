#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest pandas numpy

    mkdir -p /home/user

    python3 -c "
import os
import pandas as pd
import numpy as np

np.random.seed(42)
num_rows = 3000
timestamps = np.arange(1600000000, 1600000000 + num_rows)
np.random.shuffle(timestamps)

sensor_ids = np.random.choice(['sensor_A', 'sensor_B', 'sensor_C'], size=num_rows)
values = np.round(np.random.normal(loc=50, scale=10, size=num_rows), 2)

df = pd.DataFrame({
    'timestamp': timestamps,
    'sensor_id': sensor_ids,
    'value': values
})

df.to_csv('/home/user/sensor_data.csv', index=False)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
