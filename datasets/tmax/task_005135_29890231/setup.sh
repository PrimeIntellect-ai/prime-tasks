#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the base image required by the task
    mkdir -p /home/user/images
    touch /home/user/images/base.img

    chmod -R 777 /home/user
