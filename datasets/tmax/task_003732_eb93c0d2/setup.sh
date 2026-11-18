#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential nodejs redis-server
pip3 install pytest flask numpy redis

mkdir -p /home/user/app/backend
mkdir -p /home/user/verifier

cat << 'EOF' > /home/user/app/backend/setup.py
from setuptools import setup, Extension

module = Extension('_fast_math', sources=['_fast_math.c']) # Missing libraries=['m']

setup(
    name='fast_math',
    version='1.0',
    ext_modules=[module]
)
EOF

cat << 'EOF' > /home/user/app/backend/inference.py
import numpy as np

def run_inference(data):
    # Bug: casting to float32
    val = np.float32(data['val'])
    return val
EOF

cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
export REDIS_HOST=127.0.0.1
export REDIS_PORT=6380 # Wrong port
redis-server --port 6379 &
# Start other services here...
EOF
chmod +x /home/user/app/start_services.sh

cat << 'EOF' > /home/user/verifier/evil_payloads.json
[
  {"val": "NaN"},
  {"val": 1e11}
]
EOF

cat << 'EOF' > /home/user/verifier/clean_payloads.json
[
  {"val": 5.5},
  {"val": -100.0}
]
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
