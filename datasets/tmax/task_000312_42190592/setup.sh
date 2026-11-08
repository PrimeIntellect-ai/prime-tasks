#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    apt-get install -y ffmpeg logrotate openssh-server openssh-client espeak procps

    mkdir -p /app
    espeak -w /app/urgent_comms.wav "delta seven seven"

    mkdir -p /run/sshd
    ssh-keygen -A

    # Start sshd when a shell is spawned
    echo 'service ssh start >/dev/null 2>&1 || true' >> /etc/bash.bashrc
    echo 'service ssh start >/dev/null 2>&1 || true' >> /etc/profile

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
