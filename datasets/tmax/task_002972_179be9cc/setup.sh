#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip r-base
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
ids = np.arange(1, 101)
np.random.shuffle(ids)

dfA = pd.DataFrame({'id': ids, 'f1': np.random.randn(100)*5, 'f2': np.random.randn(100)*2, 'f3': np.random.randn(100)*10})
dfB = pd.DataFrame({'id': ids[:90], 'f4': np.random.randn(90)*3, 'f5': np.random.randn(90)*7})
dfC = pd.DataFrame({'id': ids[10:], 'f6': np.random.randn(90)*4, 'f7': np.random.randn(90)*6, 'f8': np.random.randn(90)*1})

dfA.to_csv('data_A.csv', index=False)
dfB.to_csv('data_B.csv', index=False)
dfC.to_csv('data_C.csv', index=False)
EOF

    python3 generate_data.py
    rm generate_data.py

    chmod -R 777 /home/user
