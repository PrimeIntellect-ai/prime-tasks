#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openmpi-bin libopenmpi-dev
    pip3 install pytest mpi4py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
