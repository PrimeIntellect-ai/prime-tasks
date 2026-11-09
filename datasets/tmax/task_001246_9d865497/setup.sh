#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/build_debug
cd /home/user/build_debug

python3 -c "
import json
data = {'values': [0.1, 0.2]}
with open('data.json', 'w', encoding='utf-16le') as f:
    json.dump(data, f)
"

cat << 'EOF' > processor.py
import json

def load_and_sum(filepath):
    # Bug 1: Fails to specify the correct encoding, causing decode errors or JSON serialization errors
    with open(filepath, 'r') as f:
        data = json.load(f)
    return sum(data['values'])
EOF

cat << 'EOF' > test_processor.py
from processor import load_and_sum

def test_sum():
    result = load_and_sum('data.json')
    # Bug 2: Floating point precision issue (0.1 + 0.2 != 0.3)
    assert result == 0.3
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
