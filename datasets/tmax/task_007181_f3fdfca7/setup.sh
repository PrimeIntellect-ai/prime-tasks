#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    echo "t=0.0,c=10.00|t=1.0,c=8.19|t=2.0,c=6.70|t=3.0,c=5.49|t=4.0,c=4.49|t=5.0,c=3.68" > /home/user/raw_kinetics.txt

    chmod -R 777 /home/user
