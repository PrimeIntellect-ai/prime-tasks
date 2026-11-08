#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /app/data/logs/app1
    mkdir -p /app/data/logs/app2

    # Create initial log files to satisfy the test
    echo "Initial log data" > /app/data/logs/app1/service.log
    echo "Initial log data" > /app/data/logs/app2/service.log

    # Create the vendored package
    mkdir -p /app/pylogarchiver-1.0.0/pylogarchiver

    cat << 'EOF' > /app/pylogarchiver-1.0.0/setup.py
from setuptools import setup, find_packages
setup(
    name='pylogarchiver',
    version='1.0.0',
    packages=find_packages(),
)
EOF

    cat << 'EOF' > /app/pylogarchiver-1.0.0/pylogarchiver/__init__.py
from .archiver import SafeArchiver
EOF

    cat << 'EOF' > /app/pylogarchiver-1.0.0/pylogarchiver/locker.py
import fcntl
import os

class FileLocker:
    def __init__(self, fd):
        self.fd = fd

    def lock(self):
        # Bug: bitwise AND instead of OR
        fcntl.flock(self.fd, fcntl.LOCK_EX & fcntl.LOCK_NB)

    def unlock(self):
        fcntl.flock(self.fd, fcntl.LOCK_UN)
EOF

    cat << 'EOF' > /app/pylogarchiver-1.0.0/pylogarchiver/archiver.py
import os
import tarfile
from .locker import FileLocker

class SafeArchiver:
    def __init__(self, output_path):
        self.output_path = output_path

    def add_directory(self, directory):
        with tarfile.open(self.output_path, "w:gz") as tar:
            for root, _, files in os.walk(directory):
                for file in files:
                    file_path = os.path.join(root, file)
                    arcname = os.path.relpath(file_path, directory)

                    with open(file_path, "r+b") as f:
                        locker = FileLocker(f.fileno())
                        locker.lock()
                        try:
                            tar.add(file_path, arcname=arcname)
                        finally:
                            locker.unlock()
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
