#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip protobuf-compiler time
    pip3 install pytest protobuf

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
