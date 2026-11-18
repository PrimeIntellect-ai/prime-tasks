#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    echo '{"cost": 1250.75}' > /home/user/aws_cost.json
    echo '{"cost": 845.50}' > /home/user/gcp_cost.json

    chmod -R 777 /home/user
