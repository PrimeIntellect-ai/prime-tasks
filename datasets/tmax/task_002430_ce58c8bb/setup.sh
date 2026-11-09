#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc tar gzip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/configs_raw
    cd /home/user/configs_raw
    # Create an ELF file (dummy)
    printf '\x7F\x45\x4C\x46\x01\x01\x01\x00' > plugin_alpha
    # Create a WAL file (big endian)
    printf '\x37\x7F\x06\x82\x00\x00\x00\x00' > db_tx_1
    # Create a WAL file (little endian)
    printf '\x37\x7F\x06\x83\x00\x00\x00\x00' > db_tx_2
    # Create a garbage file
    printf '\x00\x11\x22\x33\x44\x55' > unknown_blob
    # Create another ELF
    printf '\x7F\x45\x4C\x46\x02\x01\x01\x00' > plugin_beta

    tar -czf /home/user/configs.tar.gz *
    cd /home/user
    rm -rf /home/user/configs_raw

    chmod -R 777 /home/user
