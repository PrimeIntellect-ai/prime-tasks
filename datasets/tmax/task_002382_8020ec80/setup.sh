#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip software-properties-common
    pip3 install pytest

    # Install Apptainer
    add-apt-repository -y ppa:apptainer/ppa
    apt-get update
    apt-get install -y apptainer

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
