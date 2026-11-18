#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ tar gzip zip unzip
    pip3 install pytest

    mkdir -p /home/user

    mkdir -p /tmp/setup_env/assets
    mkdir -p /tmp/setup_env/docs

    printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR' > /tmp/setup_env/assets/image.dat
    printf '\x7FELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00' > /tmp/setup_env/assets/binary.txt
    printf 'PK\x03\x04\x14\x00\x00\x00\x08\x00' > /tmp/setup_env/docs/archive.bak
    echo "Hello World" > /tmp/setup_env/docs/readme.md
    printf 'OK' > /tmp/setup_env/short.bin

    cd /tmp/setup_env
    tar -cvf /tmp/source_tree.tar *
    cd /tmp
    zip inner.zip source_tree.tar
    tar -czvf /home/user/legacy_project.tar.gz inner.zip

    rm -rf /tmp/setup_env /tmp/source_tree.tar /tmp/inner.zip

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
