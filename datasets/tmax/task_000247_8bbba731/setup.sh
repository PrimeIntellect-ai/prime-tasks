#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/staging_artifacts
    mkdir -p /home/user/prod_artifacts

    # 1 MiB = 1048576 bytes
    # Staging files (Total: 80 MiB = 83886080 bytes)
    dd if=/dev/urandom of=/home/user/staging_artifacts/build_1.tar.gz bs=1048576 count=30 status=none
    dd if=/dev/urandom of=/home/user/staging_artifacts/build_2.tar.gz bs=1048576 count=30 status=none
    dd if=/dev/urandom of=/home/user/staging_artifacts/build_3.tar.gz bs=1048576 count=20 status=none

    touch -d "10 days ago" /home/user/staging_artifacts/build_1.tar.gz
    touch -d "5 days ago" /home/user/staging_artifacts/build_2.tar.gz
    touch -d "1 day ago" /home/user/staging_artifacts/build_3.tar.gz

    # Prod files (Total: 100 MiB = 104857600 bytes)
    dd if=/dev/urandom of=/home/user/prod_artifacts/log_old.log bs=1048576 count=40 status=none
    dd if=/dev/urandom of=/home/user/prod_artifacts/log_mid.log bs=1048576 count=20 status=none
    dd if=/dev/urandom of=/home/user/prod_artifacts/app_v1.jar bs=1048576 count=30 status=none
    dd if=/dev/urandom of=/home/user/prod_artifacts/app_v2.jar bs=1048576 count=10 status=none

    touch -d "20 days ago" /home/user/prod_artifacts/log_old.log
    touch -d "15 days ago" /home/user/prod_artifacts/log_mid.log
    touch -d "10 days ago" /home/user/prod_artifacts/app_v1.jar
    touch -d "2 days ago" /home/user/prod_artifacts/app_v2.jar

    chown -R user:user /home/user/staging_artifacts /home/user/prod_artifacts
    chmod -R 777 /home/user
