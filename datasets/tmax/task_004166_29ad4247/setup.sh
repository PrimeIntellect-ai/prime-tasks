#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import pandas as pd
import numpy as np
import os

def generate_data():
    np.random.seed(42)
    n = 500
    models = np.random.choice(['Vision', 'NLP'], n)
    cpu = np.random.uniform(10, 90, n)
    mem = np.random.uniform(20, 80, n)
    net = np.random.uniform(5, 50, n)
    io = np.random.uniform(1, 20, n)

    inf_time = np.where(models == 'Vision', 180, 85) + (cpu * 0.8) + (mem * 0.3) + np.random.normal(0, 15, n)

    df = pd.DataFrame({
        'Run_ID': range(n),
        'Model_Type': models,
        'CPU_Util': cpu,
        'Mem_Util': mem,
        'Net_Lat': net,
        'IO_Wait': io,
        'Inference_Time_ms': inf_time
    })

    df.to_csv('/home/user/inference_logs.csv', index=False)

if __name__ == "__main__":
    generate_data()
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
