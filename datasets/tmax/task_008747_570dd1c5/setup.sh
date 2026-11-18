#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
import pandas as pd

os.makedirs('/home/user', exist_ok=True)

# Generate thermal_model.csv
t_thermal = np.linspace(0, 50, 500)
T0, Tenv, k = 100.0, 20.0, 0.15
temp = (T0 - Tenv) * np.exp(-k * t_thermal) + Tenv
np.random.seed(101)
temp += np.random.normal(0, 0.05, size=len(t_thermal))

pd.DataFrame({'time': t_thermal, 'temperature': temp}).to_csv('/home/user/thermal_model.csv', index=False)

# Generate perf_log.csv
t_perf = np.arange(0, 20.0, 0.1)
np.random.seed(202)
response_time = 45.0 + 12.0 * np.sin(2 * np.pi * 2.5 * t_perf) + np.random.normal(0, 2.0, size=len(t_perf))

pd.DataFrame({'time': t_perf, 'response_time': response_time}).to_csv('/home/user/perf_log.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
