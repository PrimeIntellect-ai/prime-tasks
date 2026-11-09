#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip acl socat coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/shared_data
    dd if=/dev/zero of=/home/user/shared_data/dummy.dat bs=1024 count=1

    chmod -R 777 /home/user
