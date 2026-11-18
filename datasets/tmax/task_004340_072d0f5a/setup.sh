#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the dna.txt file
    echo -n "ATGCGTAACGTTGCACTAGCTAGCTGACGT" > /home/user/dna.txt

    chmod -R 777 /home/user
