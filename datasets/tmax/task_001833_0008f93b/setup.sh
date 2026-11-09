#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install hdf5-tools for test verification (h5ls)
    apt-get install -y hdf5-tools

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
