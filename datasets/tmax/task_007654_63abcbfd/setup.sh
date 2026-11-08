#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        openssh-client \
        openssl \
        gawk \
        sed \
        coreutils \
        g++

    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.ssh
    ssh-keygen -t rsa -b 2048 -f /home/user/.ssh/id_rsa -N ""

    FINGERPRINT=$(ssh-keygen -l -E md5 -f /home/user/.ssh/id_rsa.pub | awk '{print $2}' | sed 's/MD5://' | tr -d ':')

    cat << 'EOF' > /tmp/api_dump.txt
GET /api/v1/status HTTP/1.1
Host: localhost
Authorization: Bearer 555345523d61646d696e3b5045524d3d4e4f4e45
Accept: */*

GET /api/v1/audit HTTP/1.1
Host: localhost
Authorization: Bearer 555345523d61756469746f723b5045524d3d4752414e545f4155444954
Accept: */*

GET /api/v1/public HTTP/1.1
Host: localhost
Authorization: Bearer 555345523d67756573743b5045524d3d52454144
Accept: */*
EOF

    openssl enc -aes-256-cbc -pbkdf2 -in /tmp/api_dump.txt -out /home/user/api_dump.enc -pass pass:$FINGERPRINT
    rm /tmp/api_dump.txt

    chmod -R 777 /home/user
