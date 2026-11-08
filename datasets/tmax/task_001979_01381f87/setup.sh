#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential golang protobuf-compiler curl xxd
    pip3 install pytest grpcio grpcio-tools

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project

    chmod -R 777 /home/user
