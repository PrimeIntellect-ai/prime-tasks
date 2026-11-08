#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    apt-get install -y iproute2 acl g++ gawk procps tzdata

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/monitor

    chmod -R 777 /home/user
