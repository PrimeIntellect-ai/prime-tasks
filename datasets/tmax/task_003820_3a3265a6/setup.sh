#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_configs/app1
    mkdir -p /home/user/app_configs/app2
    mkdir -p /home/user/app_configs/app3
    mkdir -p /home/user/external_configs

    # Standard config files
    echo "app1 config" > /home/user/app_configs/app1/config.yml
    echo "app2 config" > /home/user/app_configs/app2/settings.json

    # Large config file (2.5 MB)
    dd if=/dev/urandom of=/home/user/app_configs/app3/huge_routing.conf bs=1024 count=2560 2>/dev/null

    # Create circular symlinks
    ln -s /home/user/app_configs/app2 /home/user/app_configs/app1/link_to_app2
    ln -s /home/user/app_configs/app1 /home/user/app_configs/app2/link_to_app1

    # External symlink
    echo "external config" > /home/user/external_configs/ext.conf
    ln -s /home/user/external_configs/ext.conf /home/user/app_configs/app3/ext_link.conf

    chown -R user:user /home/user/app_configs /home/user/external_configs
    chmod -R 777 /home/user
