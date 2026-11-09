#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/project_workspace/src
    mkdir -p /home/user/project_workspace/logs
    mkdir -p /home/user/project_workspace/data

    echo "def main(): pass" > /home/user/project_workspace/src/main.py
    echo "INFO: Started server" > /home/user/project_workspace/logs/server.log
    echo "INFO: Debug mode on" > /home/user/project_workspace/logs/debug.txt
    echo '{"key": "value"}' > /home/user/project_workspace/data/config.json

    touch -d "2 days ago" /home/user/project_workspace/src/main.py
    touch -d "2 days ago" /home/user/project_workspace/logs/server.log
    touch -d "2 days ago" /home/user/project_workspace/logs/debug.txt
    touch -d "2 days ago" /home/user/project_workspace/data/config.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
