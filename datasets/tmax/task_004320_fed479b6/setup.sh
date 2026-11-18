#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
import pandas as pd
import numpy as np

np.random.seed(123)
n = 500
F1 = np.random.normal(0, 1, n)
F2 = np.random.normal(0, 1, n)
F3 = F1 * 0.5 + np.random.normal(0, 0.1, n)
F4 = F2 * -0.8 + np.random.normal(0, 0.1, n)
F5 = np.random.normal(0, 1, n)
Target = 1.5 * F1 - 2.0 * F4 + 0.5 * (F1 * F4) + np.random.normal(0, 0.5, n)

df = pd.DataFrame({'F1': F1, 'F2': F2, 'F3': F3, 'F4': F4, 'F5': F5, 'Target': Target})
os.makedirs('/home/user', exist_ok=True)
df.to_csv('/home/user/sensor_data.csv', index=False)
"

    chmod -R 777 /home/user
