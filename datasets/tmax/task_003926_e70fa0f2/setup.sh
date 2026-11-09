#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    apt-get install -y g++ g++-aarch64-linux-gnu qemu-user locales

    locale-gen ja_JP.UTF-8
    locale-gen de_DE.UTF-8
    update-locale

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
