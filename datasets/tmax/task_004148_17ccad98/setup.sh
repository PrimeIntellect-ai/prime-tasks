#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip haproxy curl
    pip3 install pytest flask fastapi uvicorn requests

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/edge_app
    chmod -R 777 /home/user
