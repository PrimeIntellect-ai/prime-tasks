#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the initial binary file with 256 null bytes
    dd if=/dev/zero of=/home/user/app_config.bin bs=256 count=1

    chmod -R 777 /home/user
