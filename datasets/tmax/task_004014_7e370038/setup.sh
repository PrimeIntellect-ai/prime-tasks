#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        g++ \
        make \
        cmake \
        wget \
        git \
        xz-utils \
        tar \
        gzip \
        espeak \
        ffmpeg

    pip3 install pytest

    # Create directories
    mkdir -p /app/repo

    # Generate dummy binary files and pack them
    cd /app/repo
    for id in 105 302 719 884 991; do
        dd if=/dev/zero of=raw_binary.bin bs=1M count=10
        tar -czf artifact_${id}.tar.gz raw_binary.bin
        rm raw_binary.bin
    done

    # Corrupt artifact 719 by truncating it
    truncate -s -100 artifact_719.tar.gz

    # Generate audio manifest
    espeak -w /app/manifest_audio.wav "The approved artifacts for this release are one zero five, three zero two, seven one nine, and eight eight four."

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
