#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo rustc
    pip3 install pytest numpy pandas

    mkdir -p /home/user

    # Generate materials.csv
    python3 -c "
import os
import numpy as np
import pandas as pd

np.random.seed(42)
n_samples = 50

ids = np.arange(1, n_samples + 1)
density = np.random.uniform(1.0, 10.0, n_samples)
tensile_strength = np.random.uniform(100.0, 500.0, n_samples)
flexibility = -0.8 * tensile_strength + np.random.normal(0, 5.0, n_samples)
thermal = np.random.uniform(10.0, 50.0, n_samples)
electrical = np.random.uniform(1.0, 5.0, n_samples)

df = pd.DataFrame({
    'id': ids,
    'density': density,
    'tensile_strength': tensile_strength,
    'flexibility': flexibility,
    'thermal_conductivity': thermal,
    'electrical_conductivity': electrical
})

df.to_csv('/home/user/materials.csv', index=False)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
