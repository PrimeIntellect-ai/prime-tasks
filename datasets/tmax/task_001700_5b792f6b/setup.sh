#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget g++
    pip3 install pytest numpy pandas scipy

    mkdir -p /app
    wget -qO annoy.tar.gz https://files.pythonhosted.org/packages/source/a/annoy/annoy-1.17.3.tar.gz
    tar -xzf annoy.tar.gz -C /app
    rm annoy.tar.gz

    # Perturb setup.py
    sed -i "s/'src\/annoymodule.cc'/'src\/missing_module.cc'/g" /app/annoy-1.17.3/setup.py

    useradd -m -s /bin/bash user || true

    # Generate embeddings.csv
    python3 -c "
import numpy as np
import pandas as pd
np.random.seed(123)
data = np.random.randn(1000, 50)
outlier_mask = np.random.rand(1000, 50) < 0.05
data[outlier_mask] = data[outlier_mask] * 10
nan_mask = np.random.rand(1000, 50) < 0.02
data[nan_mask] = np.nan
pd.DataFrame(data).to_csv('/home/user/embeddings.csv', index=False, header=False)
"

    chmod -R 777 /home/user
