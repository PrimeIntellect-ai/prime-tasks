#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev bsdmainutils bsdextrautils
    pip3 install pytest

    # Ensure headers are found where the test expects them (Ubuntu multiarch workaround)
    mkdir -p /usr/include/sys
    ln -sf /usr/include/x86_64-linux-gnu/sys/inotify.h /usr/include/sys/inotify.h

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
