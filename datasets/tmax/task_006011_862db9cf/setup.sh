#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc zlib1g-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    echo "Initial content for alpha file. This needs to be backed up." > /home/user/data/alpha.txt
    echo "Beta file is somewhat shorter." > /home/user/data/beta.txt
    echo "Gamma file is the third file in this directory." > /home/user/data/gamma.txt

    touch -d "2023-01-01 12:00:00" /home/user/data/*.txt

    chmod -R 777 /home/user
