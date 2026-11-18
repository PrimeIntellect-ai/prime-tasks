#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libomp-dev build-essential
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
