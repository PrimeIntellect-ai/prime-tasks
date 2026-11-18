#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn numpy

    useradd -m -s /bin/bash user || true

    # Create the python script to generate the data
    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
n_samples = 200

# True latent variable
latent = np.random.normal(0, 1, n_samples)

# Generate features s1 to s5 correlated with the latent variable
s1 = latent * 1.5 + np.random.normal(0, 0.5, n_samples)
s2 = latent * 0.8 + np.random.normal(0, 0.5, n_samples)
s3 = latent * -2.0 + np.random.normal(0, 0.5, n_samples)
s4 = latent * 1.1 + np.random.normal(0, 0.5, n_samples)
s5 = latent * -0.5 + np.random.normal(0, 0.5, n_samples)

# Target variable depends on the latent variable
target = latent * 3.0 + np.random.normal(0, 1.0, n_samples)

df = pd.DataFrame({'s1': s1, 's2': s2, 's3': s3, 's4': s4, 's5': s5, 'target': target})

# Inject schema violations
df.loc[10, 's2'] = 'ERR'
df.loc[45, 's4'] = 'NaN'
df.loc[88, 'target'] = 'missing'
df.loc[150, 's1'] = np.nan

df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
