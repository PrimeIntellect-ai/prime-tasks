#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/migration
cat << 'EOF' > /home/user/migration/setup.py
import pickle

# The payload: primes that sum to 277
data = [17, 19, 23, 29, 31, 37, 41, 43, 37]

with open('/home/user/migration/payload.pkl', 'wb') as f:
    pickle.dump(data, f, protocol=2)
EOF
python3 /home/user/migration/setup.py
rm /home/user/migration/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
