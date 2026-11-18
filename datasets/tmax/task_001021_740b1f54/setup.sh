#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create vendored package directory and setup.py
    mkdir -p /app/vendored/fastcsv-1.0.4
    cat << 'EOF' > /app/vendored/fastcsv-1.0.4/setup.py
from setuptools import setup, Extension

ext_modules = [
    Extension(
        'fastcsv._c_ext',
        sources=['src/fastcsv.c'],
        # missing include_dirs=['./src']
        define_macros=[('DROP_NEWLINES', '1')] # deliberate typo
    )
]

setup(
    name='fastcsv',
    version='1.0.4',
    ext_modules=ext_modules,
    packages=['fastcsv'],
)
EOF

    # Create oracle program
    mkdir -p /app/oracle
    cat << 'EOF' > /app/oracle/reference_etl_bin
#!/usr/bin/env python3
import sys
# Dummy oracle
for line in sys.stdin:
    pass
EOF
    chmod +x /app/oracle/reference_etl_bin

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
