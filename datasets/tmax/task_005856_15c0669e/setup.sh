#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy matplotlib

    mkdir -p /home/user

    python3 -c "
import pandas as pd
import numpy as np
import os

np.random.seed(42)
df = pd.DataFrame({
    'A': np.random.randn(100),
    'B': np.random.randn(100),
    'C': np.random.randn(100),
    'D': ['cat', 'dog'] * 50
})
df.loc[5:10, 'A'] = np.nan
df.loc[20:30, 'B'] = np.nan
df.loc[1, 'C'] = 1000.0
df.loc[2, 'C'] = -1000.0

df.to_csv('/home/user/raw_data.csv', index=False)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
