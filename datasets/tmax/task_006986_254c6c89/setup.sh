#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy matplotlib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data_setup.py
import pandas as pd
import numpy as np

np.random.seed(42)
df = pd.DataFrame({
    'id': range(1, 101),
    'feature_A': np.random.normal(5, 1, 100),
    'feature_B': np.random.normal(10, 2, 100)
})
# Introduce 10 NaNs in feature_A
nan_idx = np.random.choice(100, 10, replace=False)
df.loc[nan_idx, 'feature_A'] = np.nan
# Introduce 3 massive outliers in feature_B
outlier_idx = np.random.choice(100, 3, replace=False)
df.loc[outlier_idx, 'feature_B'] = [150, 200, 250]
df.to_csv('/home/user/raw_data.csv', index=False)
EOF

    python3 /home/user/raw_data_setup.py
    rm /home/user/raw_data_setup.py

    cat << 'EOF' > /home/user/prep_data.py
import pandas as pd
import json
import numpy as np

df = pd.read_csv('/home/user/raw_data.csv')

# TODO: Impute missing values in 'feature_A' with median
# TODO: Cap 'feature_B' at 95th percentile
# TODO: Save to /home/user/cleaned_data.csv
# TODO: Save experiment_log.json with 'imputed_count_A' and 'cap_value_B'
EOF

    cat << 'EOF' > /home/user/visualize.py
import pandas as pd
import matplotlib.pyplot as plt

df = pd.read_csv('/home/user/cleaned_data.csv')
plt.plot(df['feature_B'])
# TODO: Fix backend and save to /home/user/plot.png
plt.show()
EOF

    chmod -R 777 /home/user
