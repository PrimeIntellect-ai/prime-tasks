#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    # Create directories
    mkdir -p /app/ts_processor/ts_processor
    mkdir -p /ground_truth
    mkdir -p /home/user

    # Create vendored package
    cat << 'EOF' > /app/ts_processor/setup.py
from setuptools import setup, find_packages

setup(
    name='ts_processor',
    version='0.1.0',
    packages=find_packages(),
)
EOF

    cat << 'EOF' > /app/ts_processor/ts_processor/__init__.py
from .core import process_and_validate
EOF

    cat << 'EOF' > /app/ts_processor/ts_processor/core.py
import pandas as pd

def process_and_validate(df, freq):
    # Remove duplicates
    df = df[~df.index.duplicated(keep='first')]

    # Resample and fill gaps
    resampled = df.resample(freq).mean().fllna()

    # Validate constraints
    assert resampled['value'].min() >= 0, "Values must be >= 0"
    assert resampled['value'].max() <= 100, "Values must be <= 100"
    assert resampled['value'].isna().sum() == 0, "Missing values found"

    return resampled
EOF

    # Generate raw and ground truth data
    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np

# Ground truth data
dates = pd.date_range('2023-01-01', '2023-01-10', freq='D')
values = [10.0, 20.0, np.nan, 40.0, 50.0, np.nan, 70.0, 80.0, 90.0, 100.0]
df_true = pd.DataFrame({'timestamp': dates, 'value': values})
df_true['value'] = df_true['value'].interpolate(method='linear')
df_true.to_csv('/ground_truth/expected_sensor_data.csv', index=False)

# Raw data
raw_dates = ['2023-01-01', '2023-01-01', '2023-01-02', '2023-01-02', '2023-01-04', '2023-01-05', '2023-01-05', '2023-01-07', '2023-01-08', '2023-01-09', '2023-01-10']
raw_values = [10.0, 10.0, 20.0, -50.0, 40.0, 50.0, 150.0, 70.0, 80.0, 90.0, 100.0]
df_raw = pd.DataFrame({'timestamp': raw_dates, 'value': raw_values})
df_raw.to_csv('/home/user/raw_sensor_data.csv', index=False)
EOF
    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
    chmod -R 777 /ground_truth
