#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/sys_config/network
    mkdir -p /home/user/sys_config/db/cluster
    mkdir -p /home/user/snapshots

    # Create files
    printf 'AAAAABC\n' > /home/user/sys_config/network/main.cfg
    printf '192.168.1.1111111111' > /home/user/sys_config/db/cluster/nodes.cfg
    printf 'ignore me' > /home/user/sys_config/ignore.txt

    chmod -R 777 /home/user
