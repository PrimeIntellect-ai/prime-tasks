#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy scikit-learn flask fastapi uvicorn requests setuptools

mkdir -p /app/textprep_lib-0.4.5/textprep_lib

cat << 'EOF' > /app/textprep_lib-0.4.5/setup.py
from setuptools import setup, find_packages

setup(
    name='textprep_lib',
    version='0.4.5',
    packages=find_packages(),
    install_requires=[
        'pandas',
        'numpy'
    ]
)
EOF

touch /app/textprep_lib-0.4.5/textprep_lib/__init__.py

cat << 'EOF' > /app/textprep_lib-0.4.5/textprep_lib/preprocess.py
import pandas as pd
import numpy as np

def load_and_clean(csv_path):
    df = pd.read_csv(csv_path)
    df['citations'] = df['citations'].replace('None', np.nan)
    return df
EOF

useradd -m -s /bin/bash user || true
mkdir -p /home/user/data

cat << 'EOF' > /home/user/data/abstracts.csv
abstract,citations,is_accepted
"This is a great paper on AI.",10,1
"A novel framework for deep learning.",None,1
"Bad paper with no results.",0,0
"An analysis of something.",None,0
"More research is needed.",5,1
"Another abstract here.",12,1
"Something else.",None,0
"Yet another paper.",2,0
"Final paper.",None,1
"One more for good measure.",3,1
EOF

chmod -R 777 /home/user
chmod -R 777 /app
