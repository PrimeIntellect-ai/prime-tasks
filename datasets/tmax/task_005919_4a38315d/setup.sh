#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        software-properties-common \
        tzdata

    add-apt-repository -y ppa:apptainer/ppa
    apt-get update && apt-get install -y apptainer

    pip3 install pytest

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
