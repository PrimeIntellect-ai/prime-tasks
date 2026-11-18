#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make
pip3 install pytest pandas numpy flask fastapi uvicorn

mkdir -p /home/user
cat << 'EOF' > /home/user/sensor_data.csv
sensor_A,sensor_B,sensor_C,sensor_D,target
1.0,2.0,0.5,1.1,0
2.0,4.0,1.2,-0.5,1
3.0,6.0,0.8,0.2,0
4.0,8.0,2.1,1.5,1
5.0,10.0,1.1,0.0,0
EOF

mkdir -p /app/bayes_prob_lib/bayes_prob_lib

cat << 'EOF' > /app/bayes_prob_lib/setup.py
from setuptools import setup, find_packages
setup(name='bayes_prob_lib', version='1.0.0', packages=find_packages())
EOF

cat << 'EOF' > /app/bayes_prob_lib/Makefile
build:
    gcc -shared -o dummy.so -fPIC dummy.c
EOF

cat << 'EOF' > /app/bayes_prob_lib/dummy.c
int dummy() { return 0; }
EOF

cat << 'EOF' > /app/bayes_prob_lib/bayes_prob_lib/__init__.py
from .inference import calculate_posterior
EOF

cat << 'EOF' > /app/bayes_prob_lib/bayes_prob_lib/inference.py
import numpy as n

def calculate_posterior(sensors):
    # Dummy probabilistic calculation
    val = sum(sensors.values())
    return float(1.0 / (1.0 + np.exp(-val)))
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
