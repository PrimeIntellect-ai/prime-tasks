#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang curl jq file
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/metrics-api
    chmod -R 777 /home/user
