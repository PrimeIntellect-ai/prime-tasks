#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++ make file
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/dataport

    chmod -R 777 /home/user
