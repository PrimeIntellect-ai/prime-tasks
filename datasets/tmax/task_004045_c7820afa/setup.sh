#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas dtw-python setuptools

    # Create directories
    mkdir -p /app/fast_ts_parser/fast_ts_parser
    mkdir -p /app/test_data/corpora/evil
    mkdir -p /app/test_data/corpora/clean

    # Create setup.py
    cat << 'EOF' > /app/fast_ts_parser/setup.py
from setuptools import setup, find_packages

setup(
    name='fast_ts_parser',
    version='1.0.0',
    packages=find_packages(),
)
EOF

    # Create __init__.py
    touch /app/fast_ts_parser/fast_ts_parser/__init__.py

    # Create buggy parser.py
    cat << 'EOF' > /app/fast_ts_parser/fast_ts_parser/parser.py
def parse(data):
    # Buggy implementation
    lines = data.split('\n')
    return lines
EOF

    # Install the package
    cd /app/fast_ts_parser && pip3 install -e .

    # Create dummy data files
    cat << 'EOF' > /app/test_data/reference.csv
time,value,description
1,10.0,"ref"
2,12.0,"ref"
EOF

    cat << 'EOF' > /app/test_data/corpora/clean/clean_1.csv
time,value,description
1,10.1,"clean
desc"
2,11.9,"clean"
EOF

    cat << 'EOF' > /app/test_data/corpora/evil/evil_1.csv
time,value,description
1,100.0,"evil"
2,200.0,"evil"
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
