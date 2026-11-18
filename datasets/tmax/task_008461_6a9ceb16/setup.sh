#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/mock_container
    mkdir -p /home/user/exporter

    dd if=/dev/zero of=/home/user/mock_container/data1.bin bs=1024 count=4
    dd if=/dev/zero of=/home/user/mock_container/data2.bin bs=1024 count=2

    chmod -R 777 /home/user
