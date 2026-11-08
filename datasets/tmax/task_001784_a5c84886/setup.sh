#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak tar gzip
    pip3 install pytest

    mkdir -p /app

    # Generate audio file
    espeak -w /app/rules.wav "To curate the artifact names, first extract the base name of the file, ignoring any directory paths. Remove all file extensions, meaning drop the first period and everything after it. Convert the remaining string entirely to lowercase. Replace all spaces and underscores with hyphens. Finally, append the suffix hyphen curated dot bin."

    # Create oracle script
    cat << 'EOF' > /app/oracle_namer
#!/usr/bin/env python3
import sys
import os

def curate(path):
    base = os.path.basename(path)
    if '.' in base:
        base = base.split('.', 1)[0]
    base = base.lower()
    base = base.replace(' ', '-').replace('_', '-')
    return base + "-curated.bin"

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(curate(sys.argv[1]))
EOF
    chmod +x /app/oracle_namer

    # Create user
    useradd -m -s /bin/bash user || true

    # Create artifacts archive
    mkdir -p /tmp/artifacts/dir1/dir2
    echo -n "dummy binary data 1" > "/tmp/artifacts/dir1/To_My File.v2.tar.gz"
    echo -n "dummy binary data 2" > "/tmp/artifacts/NO_EXTENSION_FILE"
    echo -n "dummy binary data 3" > "/tmp/artifacts/dir1/dir2/  leading spaces.txt"

    # Create a nested archive
    tar -czf /tmp/artifacts/nested.tar.gz -C /tmp/artifacts dir1

    # Create the final archive
    tar -czf /home/user/artifacts.tar.gz -C /tmp artifacts

    # Cleanup
    rm -rf /tmp/artifacts

    chmod -R 777 /home/user
