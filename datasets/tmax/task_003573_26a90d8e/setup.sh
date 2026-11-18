#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest pandas scipy scikit-learn fastapi uvicorn flask httpx

    mkdir -p /app/vendor/ml_prep_lib-0.1.0/ml_prep_lib
    mkdir -p /home/user

    cat << 'EOF' > /app/vendor/ml_prep_lib-0.1.0/Makefile
install:
	pip intall .   # Typo: intall instead of install
EOF

    cat << 'EOF' > /app/vendor/ml_prep_lib-0.1.0/setup.py
from setuptools import setup, find_packages

setup(
    name="ml_prep_lib",
    version="0.1.0",
    packages=find_packages(),
    install_requires=["pandas"],
)
EOF

    cat << 'EOF' > /app/vendor/ml_prep_lib-0.1.0/ml_prep_lib/__init__.py
EOF

    cat << 'EOF' > /app/vendor/ml_prep_lib-0.1.0/ml_prep_lib/core.py
import pandas as pd

def merge_sensor_data(df_main, df_ref):
    # Bug: Default merge converts missing integer references to NaN, coercing sensor_hash to float64
    merged = pd.merge(df_main, df_ref, on='sensor_id', how='left')
    return merged
EOF

    cat << 'EOF' > /home/user/main_sensors.csv
sensor_id,environment,signal_strength,feature_1,feature_2,feature_3,feature_4,feature_5,sensor_hash
1,urban,45.2,1.2,0.5,3.1,2.2,0.1,9007199254740993
2,rural,33.1,1.1,0.6,3.0,2.1,0.2,9007199254740995
3,urban,47.8,1.5,0.4,3.5,2.5,0.1,9007199254740997
4,rural,31.0,1.0,0.7,2.9,2.0,0.3,9007199254740999
5,urban,46.5,1.3,0.5,3.2,2.3,0.2,9007199254741001
EOF

    cat << 'EOF' > /home/user/ref_sensors.csv
sensor_id,calibration_val
1,0.99
3,1.01
5,1.00
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
