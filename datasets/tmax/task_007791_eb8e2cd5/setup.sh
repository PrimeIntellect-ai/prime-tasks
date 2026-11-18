#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data_source/folderA
    mkdir -p /home/user/data_source/folderB

    # Old files
    echo "old 1" > /home/user/data_source/folderA/old1.txt
    echo "old 2" > /home/user/data_source/folderB/old2.txt
    ln /home/user/data_source/folderA/old1.txt /home/user/data_source/folderB/old1_hlink.txt

    sleep 1
    touch /home/user/last_backup.ts
    sleep 1

    # New files
    echo "new 1" > /home/user/data_source/folderA/new1.txt
    echo "new 2" > /home/user/data_source/folderA/new2.txt

    # New hard links
    ln /home/user/data_source/folderA/new1.txt /home/user/data_source/folderB/new1_hlink.txt
    ln /home/user/data_source/folderA/new2.txt /home/user/data_source/folderA/new2_hlink.txt

    # Symlinks
    ln -s ../folderA/old1.txt /home/user/data_source/folderB/sym_to_old.txt
    ln -s ../folderA/new1.txt /home/user/data_source/folderB/sym_to_new.txt

    chown -R user:user /home/user/data_source
    chown user:user /home/user/last_backup.ts

    chmod -R 777 /home/user
