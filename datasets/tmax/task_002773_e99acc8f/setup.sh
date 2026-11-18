#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron jq gawk curl wget tar
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil
    mkdir -p /app/incoming_logs

    # Download and extract yq 3.2.3
    wget https://github.com/kislyuk/yq/archive/refs/tags/v3.2.3.tar.gz -O /tmp/yq-3.2.3.tar.gz
    tar -xzf /tmp/yq-3.2.3.tar.gz -C /app
    rm /tmp/yq-3.2.3.tar.gz

    # Perturb setup.py
    python3 -c "
import re
path = '/app/yq-3.2.3/setup.py'
with open(path, 'r') as f:
    content = f.read()
content = re.sub(r\"install_requires=\[.*?\]\", \"install_requires=['jq>=0.1.6', 'argcomplete>=1.8.1', 'toml>=0.10.0', 'xmltodict>=0.11.0'\", content, flags=re.DOTALL)
with open(path, 'w') as f:
    f.write(content)
"

    # Create clean corpus
    cat << 'EOF' > /app/corpora/clean/01_math.json
{"request_id": "r1", "operation": "matrix_multiply", "duration_ms": 45, "status": "success"}
{"request_id": "r2", "operation": "fast_fourier", "duration_ms": 12, "status": "failure"}
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpora/evil/02_attack.json
{"request_id": "e1", "operation": "matrix_multiply; rm -rf /", "duration_ms": 45, "status": "success"}
{"request_id": "e2", "operation": "matrix_multiply", "duration_ms": -5, "status": "success"}
{"request_id": "e3", "operation": "fast_fourier", "duration_ms": 12, "status": "pending"}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
