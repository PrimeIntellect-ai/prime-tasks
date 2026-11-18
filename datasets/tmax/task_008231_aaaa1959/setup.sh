#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/docs_raw
    cd /home/user

    # Create source files
    mkdir v1.0 v1.1 v2.0-draft
    echo "Version 1.0 docs" > v1.0/README.md
    echo -n -e '\x01\x02' > v1.0/api.bin
    echo "Version 1.1 docs" > v1.1/README.md
    echo -n -e '\x03\x04' > v1.1/api.bin
    echo "Version 2.0 draft docs" > v2.0-draft/README.md
    echo -n -e '\x05\x06\x07' > v2.0-draft/api.bin

    # Create archives
    tar -czf /home/user/docs_raw/v1.0.tar.gz v1.0
    tar -czf /home/user/docs_raw/v1.1.tar.gz v1.1
    tar -czf /home/user/docs_raw/v2.0-draft.tar.gz v2.0-draft

    # Cleanup
    rm -rf v1.0 v1.1 v2.0-draft

    chmod -R 777 /home/user
