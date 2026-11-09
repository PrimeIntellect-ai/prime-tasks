#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    python3 -c "
import numpy as np
import pandas as pd
import os

os.makedirs('/home/user', exist_ok=True)
np.random.seed(123)
time = np.linspace(0, 10, 50)
rate = 4.8 * np.exp(-0.4 * time)
rate += np.random.normal(0, 0.15, size=len(time))
pd.DataFrame({'time': time, 'rate': rate}).to_csv('/home/user/reaction_rate.csv', index=False)
"

    chmod -R 777 /home/user
