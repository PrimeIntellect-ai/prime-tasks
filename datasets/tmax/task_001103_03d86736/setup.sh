#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest setuptools

    # Create directories
    mkdir -p /app/vendored/artifact_curator-1.2.0/artifact_curator
    mkdir -p /home/user/incoming
    mkdir -p /home/user/system_fake
    mkdir -p /home/user/processed

    # Create vendored package files
    cat << 'EOF' > /app/vendored/artifact_curator-1.2.0/setup.py
from setuptools import setup, find_packages

setup(
    name='artifact_curator',
    version='1.2.0',
    packages=find_packages(),
    entry_points={
        'console_scripts': [
            'artifact-curator=artifact_curator.cli:main',
        ],
    },
)
EOF

    touch /app/vendored/artifact_curator-1.2.0/artifact_curator/__init__.py

    cat << 'EOF' > /app/vendored/artifact_curator-1.2.0/artifact_curator/extractor.py
import tarfile
import os

def extract_archive(archive_path, target_dir):
    with tarfile.open(archive_path, 'r') as tar:
        tar.extractall(path=target_dir)
EOF

    cat << 'EOF' > /app/vendored/artifact_curator-1.2.0/artifact_curator/dedup.py
import os

def deduplicate_binaries(target_dir):
    files = [os.path.join(target_dir, f) for f in os.listdir(target_dir) if os.path.isfile(os.path.join(target_dir, f))]
    for i in range(len(files)):
        for j in range(i + 1, len(files)):
            try:
                with open(files[i], 'rb') as f1, open(files[j], 'rb') as f2:
                    if f1.read() == f2.read():
                        pass
            except Exception:
                pass
EOF

    cat << 'EOF' > /app/vendored/artifact_curator-1.2.0/artifact_curator/cli.py
import sys
import os
from .extractor import extract_archive
from .dedup import deduplicate_binaries

def main():
    if len(sys.argv) != 3:
        print("Usage: artifact-curator <archive> <target_dir>")
        sys.exit(1)
    archive = sys.argv[1]
    target_dir = sys.argv[2]
    extract_archive(archive, target_dir)
    deduplicate_binaries(target_dir)

if __name__ == "__main__":
    main()
EOF

    # Generate tar files
    python3 -c "
import tarfile
import os

os.makedirs('/home/user/incoming', exist_ok=True)
os.makedirs('/home/user/system_fake', exist_ok=True)
os.makedirs('/home/user/processed', exist_ok=True)

for i in range(100):
    tar_path = f'/home/user/incoming/archive_{i}.tar'
    with tarfile.open(tar_path, 'w') as tar:
        bin_path = f'/tmp/file_{i}.bin'
        with open(bin_path, 'wb') as f:
            f.write(b'A' * 1024 * 10)
        tar.add(bin_path, arcname=f'file_{i}.bin')

        if i == 0:
            mal_path = '/tmp/malicious.txt'
            with open(mal_path, 'w') as f:
                f.write('bad')
            tar.add(mal_path, arcname='../system_fake/malicious.txt')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
