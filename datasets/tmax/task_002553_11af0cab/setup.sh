#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required data science libraries
    pip3 install numpy scipy networkx matplotlib

    # Create the user
    useradd -m -s /bin/bash user || true

    # Ensure home directory is fully writable
    chmod -R 777 /home/user
