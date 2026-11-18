#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    # Create required directories
    mkdir -p /home/user/docs_raw/chapters/ch1
    mkdir -p /home/user/docs_raw/assets
    mkdir -p /home/user/docs_packaged

    # Create required files
    echo -n "Introduction to the system." > /home/user/docs_raw/intro.md
    echo -n "Chapter 1 content goes here." > /home/user/docs_raw/chapters/ch1/content.md
    dd if=/dev/urandom of=/home/user/docs_raw/assets/architecture.bin bs=1K count=1024 status=none

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
