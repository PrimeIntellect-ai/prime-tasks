#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/cloud_storage/alice
    mkdir -p /home/user/cloud_storage/bob
    mkdir -p /home/user/cloud_storage/charlie

    head -c 100 /dev/zero > /home/user/cloud_storage/alice/app.log
    head -c 200 /dev/zero > /home/user/cloud_storage/alice/data.db
    head -c 50 /dev/zero > /home/user/cloud_storage/alice/notes.txt

    head -c 500 /dev/zero > /home/user/cloud_storage/bob/cache.tmp
    head -c 50 /dev/zero > /home/user/cloud_storage/bob/index.db

    head -c 300 /dev/zero > /home/user/cloud_storage/charlie/report.pdf
    head -c 100 /dev/zero > /home/user/cloud_storage/charlie/sys.log
    head -c 50 /dev/zero > /home/user/cloud_storage/charlie/temp.tmp

    chmod -R 777 /home/user
