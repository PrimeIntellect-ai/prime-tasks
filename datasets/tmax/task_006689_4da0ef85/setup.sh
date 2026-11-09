#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tzdata procps
    pip3 install pytest psutil pytz

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_data
    echo "dummy configuration" > /home/user/app_data/config.yml
    echo "data" > /home/user/app_data/data.txt

    chmod -R 777 /home/user
