#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip protobuf-compiler golang-go
    pip3 install pytest

    # Create directory structure
    mkdir -p /home/user/app/proto
    mkdir -p /home/user/app/corpus/clean
    mkdir -p /home/user/app/corpus/evil
    mkdir -p /home/user/app/python_logger
    mkdir -p /home/user/app/validator
    mkdir -p /home/user/app/worker

    # Create required files
    touch /home/user/app/proto/build.proto
    touch /home/user/app/.env
    touch /home/user/app/python_logger/logger.py
    touch /home/user/app/verify_e2e.sh
    touch /home/user/app/docker-compose.yml
    touch /home/user/app/worker/worker.go

    # Populate corpus files
    for i in $(seq 1 10); do
        echo '{"steps": ["echo clean"]}' > /home/user/app/corpus/clean/clean_$i.json
        echo '{"steps": ["rm -rf /"]}' > /home/user/app/corpus/evil/evil_$i.json
    done

    # Make verify script executable
    chmod +x /home/user/app/verify_e2e.sh

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
