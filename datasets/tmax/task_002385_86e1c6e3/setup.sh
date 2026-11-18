#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        golang \
        cmake \
        make \
        gcc \
        g++ \
        imagemagick

    pip3 install pytest

    mkdir -p /app
    # Create the ticket image
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'BASELINE_SEMVER: 1.14.0'" /app/ticket.png

    mkdir -p /home/user/workspace
    cat << 'EOF' > /home/user/workspace/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(PolyglotResolver)

# Missing custom command for go build
EOF

    cat << 'EOF' > /home/user/workspace/engine.go
package main

import "C"

// Missing export and concurrent semver logic
func CompareVersions() {
}

func main() {}
EOF

    cat << 'EOF' > /home/user/workspace/resolve.py
import sys
import ctypes

# Scaffolding for Python script
EOF

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/resolve_oracle.py
import sys
import re

def parse_semver(v):
    return [int(x) for x in v.split('.')]

def main():
    baseline = parse_semver("1.14.0")
    valid_packages = []
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) != 2:
            continue
        pkg, ver = parts
        v = parse_semver(ver)
        if v >= baseline:
            valid_packages.append(pkg)

    # Simple radix trie implementation and pre-order traversal would go here
    # (Oracle implementation)
    pass

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
    chmod -R 777 /opt/oracle
