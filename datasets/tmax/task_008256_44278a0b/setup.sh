#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/projects/proj_alpha
    mkdir -p /home/user/projects/proj_beta
    mkdir -p /home/user/projects/proj_gamma
    mkdir -p /home/user/projects/proj_delta
    touch /home/user/.profile

    dd if=/dev/zero of=/home/user/projects/proj_alpha/data.bin bs=1M count=50
    dd if=/dev/zero of=/home/user/projects/proj_beta/data.bin bs=1M count=10
    dd if=/dev/zero of=/home/user/projects/proj_gamma/data.bin bs=1M count=100
    dd if=/dev/zero of=/home/user/projects/proj_delta/data.bin bs=1M count=5

    chmod -R 777 /home/user
