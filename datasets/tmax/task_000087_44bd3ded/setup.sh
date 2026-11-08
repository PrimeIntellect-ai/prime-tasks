#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar
    pip3 install pytest

    # Create the fast-archive-parser package
    mkdir -p /app/fast-archive-parser/fast_archive
    cat << 'EOF' > /app/fast-archive-parser/setup.py
import os
from setuptools import setup, find_packages

if os.environ.get('ALLOW_BUILD') != 'true':
    raise RuntimeError("Build not allowed")

setup(
    name="fast-archive-parser",
    version="1.2",
    packages=find_packages(),
)
EOF

    cat << 'EOF' > /app/fast-archive-parser/fast_archive/__init__.py
# Dummy fast archive parser module
def extract():
    pass
EOF

    # Create the incoming repository archive
    mkdir -p /home/user/incoming
    mkdir -p /tmp/repo_creation/logs
    mkdir -p /tmp/repo_creation/bins

    cat << 'EOF' > /tmp/repo_creation/logs/artifact1.log
[START ARTIFACT]
Artifact-ID: bin-001
Checksum: 1111
Status: VALID
[END ARTIFACT]
[START ARTIFACT]
Artifact-ID: bin-002
Checksum: 2222
Status: INVALID
[END ARTIFACT]
[START ARTIFACT]
Artifact-ID: bin-003
Checksum: 3333
Status: VALID
[END ARTIFACT]
EOF

    touch /tmp/repo_creation/bins/bin-001
    touch /tmp/repo_creation/bins/bin-002
    touch /tmp/repo_creation/bins/bin-003

    cd /tmp/repo_creation && tar -czf /home/user/incoming/repository.tar.gz .
    rm -rf /tmp/repo_creation

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
