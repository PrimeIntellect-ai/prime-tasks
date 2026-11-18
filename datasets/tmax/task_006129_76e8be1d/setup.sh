#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user
    echo "4 5 7 3 5 6 4 5 3 8 4 5 6 3 4 5 5 6 4 3" > /home/user/counts.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
