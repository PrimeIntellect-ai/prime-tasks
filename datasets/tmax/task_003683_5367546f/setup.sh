#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages for the task
    apt-get install -y protobuf-compiler protobuf-c-compiler libprotobuf-c-dev gcc make

    # Create the required directory
    mkdir -p /home/user/polybuild

    # Create the user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
