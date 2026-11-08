#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the monitored_pids.txt file.
    # We use PID 1 for the active processes since it is guaranteed to be running in the container.
    mkdir -p /home/user
    echo "1" > /home/user/monitored_pids.txt
    echo "1" >> /home/user/monitored_pids.txt
    echo "999999" >> /home/user/monitored_pids.txt

    chmod -R 777 /home/user
