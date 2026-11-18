#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    python3 -c "
import numpy as np
import pandas as pd

np.random.seed(123)
cycles = np.linspace(0, 500, 200)
true_capacity = 1.5 * np.exp(-0.005 * cycles) + 0.2
noise = np.random.normal(0, 0.05, size=len(cycles))
capacity = true_capacity + noise

df = pd.DataFrame({'cycle': cycles, 'capacity': capacity})
df.to_csv('/home/user/raw_battery_data.csv', index=False)
"

    chmod -R 777 /home/user
