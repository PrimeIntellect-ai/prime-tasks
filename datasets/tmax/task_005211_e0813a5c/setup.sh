#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn fastapi uvicorn requests setuptools

    # Create user
    useradd -m -s /bin/bash user || true

    # Create vendored package
    mkdir -p /app/datacleaner-1.2.0/datacleaner

    cat << 'EOF' > /app/datacleaner-1.2.0/setup.py
from setuptools import setup, find_packages

setup(
    name='datacleaner',
    version='1.2.0',
    packages=find_packages(),
    install_requires=['pandas']
)
EOF

    cat << 'EOF' > /app/datacleaner-1.2.0/datacleaner/__init__.py
from .schema import enforce_age_schema
EOF

    cat << 'EOF' > /app/datacleaner-1.2.0/datacleaner/schema.py
import pandas as pd

def enforce_age_schema(df):
    df['age'] = pd.to_numeric(df['age'], errors='coerce')
    return df
EOF

    # Create raw data
    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/raw_users.csv
age,income,category,is_active
25,50000.0,A,1
twenty,,B,0
30,60000.0,A,1
45,80000.0,C,1
invalid,40000.0,B,0
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
