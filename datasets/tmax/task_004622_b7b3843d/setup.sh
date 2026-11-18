#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pyyaml

    # Create directories
    mkdir -p /app/vendored/lzconfig_v1.0.0/lzconfig
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil
    mkdir -p /home/user/approved_configs

    # Create vendored package setup.py
    cat << 'EOF' > /app/vendored/lzconfig_v1.0.0/setup.py
from setuptools import setup, find_packages
setup(name="lzconfig", version="1.0.0", packages=find_packages())
EOF

    # Create vendored package __init__.py
    cat << 'EOF' > /app/vendored/lzconfig_v1.0.0/lzconfig/__init__.py
from .core import decompress
EOF

    # Create vendored package core.py (missing imports)
    cat << 'EOF' > /app/vendored/lzconfig_v1.0.0/lzconfig/core.py
def decompress(data):
    decompressed_bytes = zlib.decompress(data)
    return json.loads(decompressed_bytes.decode('utf-8'))
EOF

    # Generate corpus files
    python3 -c "
import os
import json
import zlib

def write_lzc(path, data):
    with open(path, 'wb') as f:
        f.write(zlib.compress(json.dumps(data).encode('utf-8')))

write_lzc('/app/corpus/clean/clean1.lzc', {'theme': 'dark', 'log_dir': 'logs/'})
write_lzc('/app/corpus/clean/clean2.lzc', {'role': 'user', 'data_path': 'data/db.sqlite'})

write_lzc('/app/corpus/evil/evil1.lzc', {'role': 'admin'})
write_lzc('/app/corpus/evil/evil2.lzc', {'plugin_path': '/etc/plugins'})
write_lzc('/app/corpus/evil/evil3.lzc', {'_internal_state': 1})
write_lzc('/app/corpus/evil/evil4.lzc', {'log_dir': '../logs'})
"

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
