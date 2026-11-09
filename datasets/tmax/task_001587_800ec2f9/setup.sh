#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/deploy/v1
    mkdir -p /home/user/deploy/v2
    mkdir -p /home/user/deploy/v3
    mkdir -p /home/user/monitor

    # v1 - Good deployment
    python3 -c "import socket as s; sock = s.socket(s.AF_UNIX); sock.bind('/home/user/deploy/v1/app.sock')"
    echo "TZ=UTC\nLANG=en_US.UTF-8" > /home/user/deploy/v1/config.meta

    # v2 - Bad socket (regular file)
    touch /home/user/deploy/v2/app.sock
    echo "TZ=UTC\nLANG=en_US.UTF-8" > /home/user/deploy/v2/config.meta

    # v3 - Bad config
    python3 -c "import socket as s; sock = s.socket(s.AF_UNIX); sock.bind('/home/user/deploy/v3/app.sock')"
    echo "TZ=EST\nLANG=fr_FR.UTF-8" > /home/user/deploy/v3/config.meta

    # Set initial symlink
    ln -s /home/user/deploy/v2 /home/user/deploy/current

    chmod -R 777 /home/user
