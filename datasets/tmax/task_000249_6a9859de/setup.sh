#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_config/dirA
    mkdir -p /home/user/backup_chunks

    /bin/bash -c "printf 'A%.0s' {1..120} > /home/user/app_config/file1.conf"
    /bin/bash -c "printf 'B%.0s' {1..50} > /home/user/app_config/file2.conf"
    touch -d "2 days ago" /home/user/app_config/file2.conf
    /bin/bash -c "printf 'C%.0s' {1..130} > /home/user/app_config/file3.conf"

    ln -s ../ /home/user/app_config/dirA/link_back
    ln -s dirA/link_back /home/user/app_config/loop_entry

    chown -R user:user /home/user
    chmod -R 777 /home/user
