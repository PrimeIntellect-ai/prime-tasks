#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/config_root/sub_dir
    mkdir -p /home/user/config_root/loop_dir

    echo -n "server_name=app;   " > /home/user/config_root/app.conf
    echo -n "host=127.0.0.1;port=5432;" > /home/user/config_root/db.conf
    echo -n "mode=active;retry=3;" > /home/user/config_root/sub_dir/service.conf
    echo -n "padding=xxxxxxxxxxxxxxx;" > /home/user/config_root/sub_dir/pad.conf

    ln -s /home/user/config_root/loop_dir /home/user/config_root/loop_dir/symlink_loop
    ln -s /home/user/config_root/app.conf /home/user/config_root/app_link.conf

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
