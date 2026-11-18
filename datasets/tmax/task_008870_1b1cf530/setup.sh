#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ coreutils tar gzip
    pip3 install pytest

    mkdir -p /home/user/drafts

    # Create .txt files
    echo "Apple docs" > /home/user/drafts/apple.txt
    echo "Zebra docs" > /home/user/drafts/zebra.txt
    echo "Mango docs" > /home/user/drafts/mango.txt
    echo "Banana docs" > /home/user/drafts/banana.txt
    echo "Cherry docs" > /home/user/drafts/cherry.txt

    # Create .dat files
    head -c 250000 /dev/urandom > /home/user/drafts/diagram.dat
    head -c 150000 /dev/urandom > /home/user/drafts/screenshot.dat

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/drafts
    chmod -R 777 /home/user
