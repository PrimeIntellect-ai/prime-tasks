#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    # Create the backup file
    head -c 1024 /dev/urandom > backup.tar.gz

    # Create the old pinned hash and add it to a binary
    OLD_HASH="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    echo -n "$OLD_HASH" > /tmp/pins.txt
    cp /bin/ls app_binary
    objcopy --add-section .cert_pins=/tmp/pins.txt --set-section-flags .cert_pins=alloc,readonly app_binary
    rm /tmp/pins.txt

    chmod -R 777 /home/user
