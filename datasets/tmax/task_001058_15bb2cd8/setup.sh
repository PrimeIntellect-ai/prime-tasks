#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create initial state for the task
    mkdir -p /home/user/service_data
    echo "dummyuser:x:1000:1000:Dummy:/home/dummy:/bin/bash" > /home/user/service_data/passwd

    chmod -R 777 /home/user
