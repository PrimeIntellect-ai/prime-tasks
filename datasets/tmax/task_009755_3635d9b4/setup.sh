#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/app_data/module_a
    mkdir -p /home/user/app_data/module_b/nested

    echo "Log entry 1" > /home/user/app_data/module_a/access.log
    echo "Log entry 2" > /home/user/app_data/module_a/error.log
    echo "Log entry 3" > /home/user/app_data/module_b/system.log
    echo "Nested log" > /home/user/app_data/module_b/nested/deep.log

    echo "Binary data" > /home/user/app_data/module_b/data.bin

    ln -s /home/user/app_data/module_a /home/user/app_data/module_a/loop_dir
    ln -s /home/user/app_data/module_b/nested /home/user/app_data/module_b/loop2_dir
    ln -s /home/user/app_data/module_a/access.log /home/user/app_data/module_a/symlink.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
