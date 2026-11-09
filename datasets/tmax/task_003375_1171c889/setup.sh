#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create vendored package directory
    mkdir -p /app/py-archiver-1.0.0/pyarchiver

    # Create setup.py
    cat << 'EOF' > /app/py-archiver-1.0.0/setup.py
from setuptools import setup, find_packages

setup(
    name='py-archiver',
    version='1.0.0',
    packages=find_packages(),
)
EOF

    # Create pyarchiver/__init__.py
    touch /app/py-archiver-1.0.0/pyarchiver/__init__.py

    # Create pyarchiver/core.py with bugs
    cat << 'EOF' > /app/py-archiver-1.0.0/pyarchiver/core.py
import os
import fcntl

BUFFER_SIZE = 1

def archive_directory(source_dir, dest_dir, chunk_size):
    for f in os.listdir(source_dir):
        filepath = os.path.join(source_dir, f)
        if os.path.isfile(filepath):
            with open(filepath, 'rb') as file:
                while True:
                    chunk = file.read(BUFFER_SIZE)
                    if not chunk:
                        break
EOF

    # Create pyarchiver/cli.py
    cat << 'EOF' > /app/py-archiver-1.0.0/pyarchiver/cli.py
import argparse
from .core import archive_directory

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', required=True)
    parser.add_argument('--dest', required=True)
    parser.add_argument('--chunk-size', required=True)
    args = parser.parse_args()
    archive_directory(args.source, args.dest, args.chunk_size)

if __name__ == '__main__':
    main()
EOF

    # Create directories for the task
    mkdir -p /home/user/app_data
    mkdir -p /home/user/archives

    # Set permissions
    chmod -R 777 /app
    chmod -R 777 /home/user
