#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ iputils-ping tzdata
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Ensure clean state
    rm -rf /home/user/deploy_blue /home/user/deploy_green /home/user/observability.log /home/user/raw_fs.txt /home/user/agent.cpp /home/user/deploy.sh /home/user/agent_bin

    chmod -R 777 /home/user
