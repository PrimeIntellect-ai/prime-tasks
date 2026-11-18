#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_artifacts
    mkdir -p /home/user/curated_repo
    mkdir -p /home/user/backup

    dd if=/dev/urandom of="/home/user/raw_artifacts/app_v1.exe" bs=1024 count=150
    dd if=/dev/urandom of="/home/user/raw_artifacts/Network Tool v2.out" bs=1024 count=120
    dd if=/dev/urandom of="/home/user/raw_artifacts/script_file" bs=1024 count=110
    dd if=/dev/urandom of="/home/user/raw_artifacts/small_app.exe" bs=1024 count=50
    dd if=/dev/urandom of="/home/user/raw_artifacts/library.so" bs=1024 count=200

    chmod -R 777 /home/user
    chmod a-x "/home/user/raw_artifacts/library.so"
