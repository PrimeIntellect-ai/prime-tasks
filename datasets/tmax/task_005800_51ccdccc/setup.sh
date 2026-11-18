#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar gzip coreutils
    pip3 install pytest

    mkdir -p /home/user/setup_temp
    cd /home/user/setup_temp

    # Team A: Valid zip
    mkdir team_a
    echo -n "This is the API documentation." > team_a/api.md
    echo -n "Setup instructions." > team_a/setup.md
    zip -r team_a.zip team_a

    # Team B: Valid tar.gz
    mkdir team_b
    echo -n "Architecture diagrams and notes." > team_b/architecture.md
    tar -czf team_b.tar.gz team_b

    # Team C: Corrupted zip
    head -c 100 /dev/urandom > team_c.zip

    # Team D: compressed md stream
    echo -n "Miscellaneous deployment notes." | gzip > deployment.md.gz

    # Create the master tar
    tar -cf /home/user/docs_archive.tar team_a.zip team_b.tar.gz team_c.zip deployment.md.gz

    # Cleanup
    cd /home/user
    rm -rf /home/user/setup_temp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
