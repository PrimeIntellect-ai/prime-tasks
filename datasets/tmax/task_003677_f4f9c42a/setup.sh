#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas

# Create package structure
mkdir -p /app/ml_artifact_tracker-0.1.0/tracker
cat << 'EOF' > /app/ml_artifact_tracker-0.1.0/setup.py
from setuptools import setup, find_packages
setup(
    name='ml_artifact_tracker',
    version='0.1.0',
    packages=find_packages(),
    install_requires=['pandas>3.0.0']
)
EOF

touch /app/ml_artifact_tracker-0.1.0/tracker/__init__.py

cat << 'EOF' > /app/ml_artifact_tracker-0.1.0/tracker/core.py
import cPickle as pickle

class Tracker:
    def __init__(self):
        pass
EOF

# Create corpora directories
mkdir -p /app/corpora/evil
mkdir -p /app/corpora/clean

# Generate corpora
python3 -c "
import json
import random

# Generate Clean
for i in range(50):
    data = {
        'artifact_id': f'clean_{i:03d}',
        'schema_version': 'v2',
        'status': 'SUCCESS',
        'metrics': {
            'loss': random.uniform(0.1, 2.0),
            'accuracy': random.uniform(0.5, 1.0)
        }
    }
    if random.choice([True, False]):
        data['model_size_mb'] = random.randint(10, 100)
    else:
        data['artifacts'] = {'model_size_mb': random.randint(10, 100)}

    with open(f'/app/corpora/clean/clean_{i:03d}.json', 'w') as f:
        json.dump(data, f)

# Generate Evil
for i in range(50):
    data = {
        'artifact_id': f'evil_{i:03d}',
        'schema_version': 'v2',
        'status': 'SUCCESS',
        'metrics': {
            'loss': random.uniform(0.1, 2.0),
            'accuracy': random.uniform(0.5, 1.0)
        },
        'model_size_mb': random.randint(10, 100)
    }

    # Corrupt one property
    err = random.randint(1, 5)
    if err == 1:
        data['schema_version'] = 'v1'
    elif err == 2:
        data['status'] = 'FAILED'
    elif err == 3:
        data['metrics']['loss'] = 3.0
    elif err == 4:
        data['metrics']['accuracy'] = 0.4
    elif err == 5:
        data['model_size_mb'] = 5

    with open(f'/app/corpora/evil/evil_{i:03d}.json', 'w') as f:
        json.dump(data, f)
"

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
