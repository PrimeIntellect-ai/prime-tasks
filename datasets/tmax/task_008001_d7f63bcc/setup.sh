#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc coreutils
    pip3 install pytest

    mkdir -p /home/user/cache_a /home/user/cache_b /home/user/cache_c
    dd if=/dev/zero of=/home/user/cache_a/data.bin bs=1M count=50 2>/dev/null
    dd if=/dev/zero of=/home/user/cache_b/data.bin bs=1M count=10 2>/dev/null
    dd if=/dev/zero of=/home/user/cache_c/data.bin bs=1M count=100 2>/dev/null

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
