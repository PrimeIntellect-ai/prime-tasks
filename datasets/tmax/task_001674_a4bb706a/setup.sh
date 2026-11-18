#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git sleuthkit e2fsprogs build-essential python3-dev
    pip3 install pytest

    mkdir -p /app/vendored_logparser-1.2.0/src
    mkdir -p /app/vendored_logparser-1.2.0/logparser

    cat << 'EOF' > /app/vendored_logparser-1.2.0/setup.py
from setuptools import setup, Extension
setup(
    name='vendored_logparser',
    version='1.2.0',
    packages=['logparser'],
    ext_modules=[Extension('logparser.fast', sources=['src/parser_c.c'])],
)
EOF
    touch /app/vendored_logparser-1.2.0/src/parser.c
    touch /app/vendored_logparser-1.2.0/logparser/__init__.py

    dd if=/dev/zero of=/app/server_disk.img bs=1M count=10
    mkfs.ext4 /app/server_disk.img
    echo -n "CRASH_INP:[ERROR] 2023-01-01 :: Malformed \x00\x00 buffer::overflow" > /tmp/core.dump
    debugfs -w -R "write /tmp/core.dump core.dump" /app/server_disk.img
    debugfs -w -R "rm core.dump" /app/server_disk.img
    rm /tmp/core.dump

    mkdir -p /app/internal_tools
    cd /app/internal_tools
    git init
    git config user.email "admin@example.com"
    git config user.name "Admin"

    cat << 'EOF' > parser_oracle_bin
#!/usr/bin/env python3
import sys
print(f"Parsed: {sys.argv[1]}")
EOF
    chmod +x parser_oracle_bin

    git add parser_oracle_bin
    git commit -m "Add parser oracle binary"
    git rm parser_oracle_bin
    git commit -m "Oops, delete oracle binary"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
