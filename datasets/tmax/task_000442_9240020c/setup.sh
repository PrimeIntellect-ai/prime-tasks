#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar
    pip3 install pytest setuptools

    # Create research_packer package
    mkdir -p /app/research_packer/research_packer

    cat << 'EOF' > /app/research_packer/setup.py
from setuptools import setup, find_packages
setup(
    name='research_packer',
    version='1.0.0',
    packages=find_packages(),
)
EOF

    touch /app/research_packer/research_packer/__init__.py

    cat << 'EOF' > /app/research_packer/research_packer/core.py
import sys
import zlib

CHUNK_SIZE = 16

def pack_stream(target_file, append=False):
    mode = 'ab' if append else 'wb'
    with open(target_file, mode) as f:
        while True:
            chunk = sys.stdin.buffer.read(CHUNK_SIZE)
            if not chunk:
                break
            compressed = zlib.compress(chunk)
            f.write(compressed)
EOF

    cat << 'EOF' > /app/research_packer/research_packer/__main__.py
import argparse
from .core import pack_stream

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['pack'])
    parser.add_argument('--append', action='store_true')
    parser.add_argument('target_file')
    args = parser.parse_args()

    if args.action == 'pack':
        pack_stream(args.target_file, append=args.append)

if __name__ == '__main__':
    main()
EOF

    # Generate test data
    mkdir -p /home/user/incoming_data
    mkdir -p /tmp/data_gen

    for i in 1 2 3 4 5; do
        echo "timestamp,sensor_id,value_1,value_2,value_3,status,error_code,notes" > /tmp/data_gen/data_${i}.csv
        for j in $(seq 1 150000); do
            echo "2023-01-01T00:00:00Z,sensor_001,0.000,0.000,0.000,OK,0,none" >> /tmp/data_gen/data_${i}.csv
        done

        cd /tmp/data_gen
        zip data_${i}.zip data_${i}.csv > /dev/null
        tar -czf /home/user/incoming_data/archive_${i}.tar.gz data_${i}.zip
        rm data_${i}.csv data_${i}.zip
    done

    rm -rf /tmp/data_gen

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
