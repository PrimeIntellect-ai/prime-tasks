#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl tar
    pip3 install pytest numpy

    mkdir -p /app
    cd /app
    pip3 download --no-binary :all: --no-deps tablib==0.14.0
    tar -xzf tablib-0.14.0.tar.gz
    rm tablib-0.14.0.tar.gz

    # Inject the deliberate perturbation
    echo 'import os' >> /app/tablib-0.14.0/setup.py
    echo 'os.environ["FORCE_FAIL"] = "1"' >> /app/tablib-0.14.0/setup.py

    # Create oracle program
    cat << 'EOF' > /app/oracle_etl_pipeline.py
import sys
import tablib
import numpy as np
import json

def run_oracle(csv_path, json_path):
    with open(csv_path, 'r') as f:
        csv_data = tablib.Dataset().load(f.read(), format='csv')
    with open(json_path, 'r') as f:
        json_data = json.load(f)

    # join logic and math
    # output exact covariance matrix formatted to 4 decimal places

if __name__ == "__main__":
    run_oracle(sys.argv[1], sys.argv[2])
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
