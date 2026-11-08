#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip openssl apache2-utils socat netcat-openbsd ncat
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/deployments_staging
    cd /home/user
    mkdir -p app-v1/assets app-v2/assets

    echo "Version 1" > app-v1/index.html
    echo "Version 2" > app-v2/index.html

    dd if=/dev/urandom of=app-v1/assets/image1.jpg bs=1024 count=50
    dd if=/dev/urandom of=app-v1/assets/video1.mp4 bs=1024 count=150
    dd if=/dev/urandom of=app-v2/assets/image1.jpg bs=1024 count=80
    dd if=/dev/urandom of=app-v2/assets/video1.mp4 bs=1024 count=200

    tar -czf backup.tar.gz app-v1 app-v2
    rm -rf app-v1 app-v2

    chmod -R 777 /home/user
