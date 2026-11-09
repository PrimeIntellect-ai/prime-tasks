#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user/etc_backup/nested
    mkdir -p /home/user/etc_mock/nested

    echo -n "AAAAABBBBB" > /home/user/etc_backup/app.conf
    echo -n "ZZZZZ" > /home/user/etc_backup/db.conf
    echo -n "TTTTT" > /home/user/etc_backup/nested/cache.conf

    echo -n "AAAAACCCCC" > /home/user/etc_mock/app.conf
    echo -n "ZZZZZ" > /home/user/etc_mock/db.conf
    echo -n "TTTTT" > /home/user/etc_mock/nested/cache.conf
    echo -n "XXXYYY" > /home/user/etc_mock/new.conf

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
