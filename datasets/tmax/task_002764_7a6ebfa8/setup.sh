#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang ffmpeg espeak tar
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/transmission.wav "delta charlie seven"

    mkdir -p /tmp/tar_build
    cd /tmp/tar_build
    touch readme.txt
    mkdir data loop
    touch data/info.json
    ln -s ../loop loop/cycle
    ln -s cycle loop/trick
    ln -s readme.txt valid_link
    tar -cf /app/artifacts.tar *

    mkdir -p /home/user/curator
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
