#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make g++-aarch64-linux-gnu
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/workspace
    echo -n "random noise [CMD: init] more noise [CMD: st[CMD: start] ignore [CMD: execute] done." > /home/user/input.txt

    chmod -R 777 /home/user
