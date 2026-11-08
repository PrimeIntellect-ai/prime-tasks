#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest packaging

    mkdir -p /app

    # Generate the requirements.wav file
    espeak -w /app/requirements.wav "Hi, it's Alex. For the new artifact resolver, we need strict ABI compliance. Only select libraries with the 'sysv' ABI. We've had breaking changes in version 3, so reject any library version greater than or equal to 3.0.0. Also, strictly ignore any library that has 'experimental' in its metadata. If multiple valid versions of a library exist, always pick the one with the highest semantic version. Finally, resolve the dependencies using a breadth-first search starting from the target library, and if a library is already in the resolved list, skip it to avoid duplicates."

    # Create the oracle resolver
    cat << 'EOF' > /app/oracle_resolver
#!/usr/bin/env python3
import sys
import json
import argparse
from packaging.version import Version, InvalidVersion
from collections import deque

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--db', required=True)
    parser.add_argument('--target', required=True)
    args = parser.parse_args()

    with open(args.db) as f:
        db = json.load(f)

    valid_libs = []
    for lib in db:
        if lib.get('abi') != 'sysv':
            continue
        try:
            v = Version(lib.get('version', '0.0.0'))
        except InvalidVersion:
            continue
        if v >= Version('3.0.0'):
            continue
        if 'experimental' in lib.get('metadata', []):
            continue
        valid_libs.append(lib)

    best_libs = {}
    for lib in valid_libs:
        name = lib['name']
        v = Version(lib['version'])
        if name not in best_libs or v > Version(best_libs[name]['version']):
            best_libs[name] = lib

    if args.target not in best_libs:
        return

    resolved = []
    visited = set()
    queue = deque([args.target])

    while queue:
        curr = queue.popleft()
        if curr in visited:
            continue
        visited.add(curr)

        if curr in best_libs:
            lib = best_libs[curr]
            resolved.append(f"{curr}.so.{lib['version']}")
            for dep in lib.get('deps', []):
                if dep not in visited:
                    queue.append(dep)

    for r in resolved:
        print(r)

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle_resolver

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
