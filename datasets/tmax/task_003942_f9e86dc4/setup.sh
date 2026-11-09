#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential zlib1g-dev wget tar gzip
    pip3 install pytest

    # Setup vendored package
    mkdir -p /app/vendored
    cd /app/vendored
    wget https://zlib.net/pigz/pigz-2.8.tar.gz
    tar -xzf pigz-2.8.tar.gz
    rm pigz-2.8.tar.gz
    sed -i 's/-lz//g' /app/vendored/pigz-2.8/Makefile

    # Setup corpora
    mkdir -p /app/corpora/clean /app/corpora/evil
    mkdir -p /tmp/setup_clean /tmp/setup_evil

    # Clean corpus setup
    cd /tmp/setup_clean
    mkdir -p docs/nested
    echo "safe data" > docs/safe.txt
    ln -s safe.txt docs/safelink
    tar -czf docs/nested/internal.tar.gz docs/safe.txt
    tar -czf /app/corpora/clean/clean_backup1.tar.gz docs/

    # Evil corpus setup
    cd /tmp/setup_evil
    mkdir -p payload/deep
    echo "malicious data" > payload/bad.txt
    ln -s /etc/shadow payload/abs_link
    ln -s ../../../../../etc/passwd payload/rel_link
    mkdir -p payload/nested_bomb
    ln -s /root payload/nested_bomb/root_link
    tar -czf payload/deep/hidden_evil.tar.gz payload/nested_bomb/
    tar -czf /app/corpora/evil/evil_backup1.tar.gz payload/

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
