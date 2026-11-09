#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    # Create the required samples.csv file
    python3 -c "
import numpy as np
import pandas as pd
import os

os.makedirs('/home/user', exist_ok=True)
np.random.seed(123)
# Simulate MCMC samples (e.g., from a skewed posterior)
samples = np.random.gamma(shape=2.0, scale=0.5, size=5000)
df = pd.DataFrame({'theta': samples})
df.to_csv('/home/user/samples.csv', index=False)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
