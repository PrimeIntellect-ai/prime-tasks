#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/workspace
    mkdir -p /home/user/edge_fleet/node_1/versions/v1
    mkdir -p /home/user/edge_fleet/node_2/versions/v1
    mkdir -p /home/user/edge_fleet/node_3/versions/v1

    echo "8081" > /home/user/edge_fleet/node_1/config.txt
    echo "8082" > /home/user/edge_fleet/node_2/config.txt
    echo "8083" > /home/user/edge_fleet/node_3/config.txt

    for i in 1 2 3; do
        touch /home/user/edge_fleet/node_$i/versions/v1/monitor
        chmod +x /home/user/edge_fleet/node_$i/versions/v1/monitor
        ln -sfn /home/user/edge_fleet/node_$i/versions/v1 /home/user/edge_fleet/node_$i/current
    done

    chmod -R 777 /home/user
