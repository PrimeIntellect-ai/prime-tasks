#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /home/user

    # Create the pyc file
    cat << 'EOF' > risk_model.py
import math

def calculate_risk(x):
    # This naive formula suffers from catastrophic cancellation for small x
    return 1.0 - math.cos(x)
EOF
    python3 -c "import py_compile; py_compile.compile('risk_model.py', cfile='risk_model.pyc')"
    rm risk_model.py

    # Create the memory dump
    head -c 500000 /dev/urandom | base64 > crash.dmp
    echo '[TICKET-9921-DATA] {"x": 1.23456789e-8}' >> crash.dmp
    head -c 500000 /dev/urandom | base64 >> crash.dmp

    chmod -R 777 /home/user
