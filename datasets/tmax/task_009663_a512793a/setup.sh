#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libhdf5-dev hdf5-tools gawk coreutils
    pip3 install pytest

    mkdir -p /home/user
    tr '\0' 'A' < /dev/zero | head -c 1000 > /home/user/sequence.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
