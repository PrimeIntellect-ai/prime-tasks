#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install C compiler and math libraries
    apt-get install -y gcc make libc-dev libgsl-dev liblapacke-dev libopenblas-dev

    # Create user
    useradd -m -s /bin/bash user || true

    # Create initial data
    mkdir -p /home/user
    echo "-2.0,-2.1,-1.0,2.8,0.0,1.5,1.0,1.2,2.0,9.1" > /home/user/data.csv

    # Set permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user
