#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip iputils-ping logrotate
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    echo '["127.0.0.1", "198.51.100.254"]' > /home/user/targets.json

    chmod -R 777 /home/user
