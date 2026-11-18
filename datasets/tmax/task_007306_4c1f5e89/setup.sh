#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip qemu-system-x86 logrotate
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the dummy legacy image
    truncate -s 10M /home/user/legacy.img

    # Ensure .profile exists
    touch /home/user/.profile

    chmod -R 777 /home/user
