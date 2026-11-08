#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/polybuild/src
    cat << 'EOF' > /home/user/polybuild/src/app.py
import sys
import os
import zlib
import base64
from collections import defaultdict

def main():
    print("Hello, world!")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
