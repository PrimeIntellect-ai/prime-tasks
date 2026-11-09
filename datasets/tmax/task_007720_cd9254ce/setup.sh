#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create task directories and files
    mkdir -p /home/user/dataset/folderA
    mkdir -p /home/user/dataset/folderB

    # Create target files
    head -c 60000 /dev/urandom > /home/user/dataset/file1.dat
    head -c 100000 /dev/urandom > /home/user/dataset/folderA/file2.dat

    # Create ignored files (wrong size, wrong extension)
    head -c 40000 /dev/urandom > /home/user/dataset/folderA/small.dat
    head -c 80000 /dev/urandom > /home/user/dataset/folderB/file3.txt

    # Create symlink loops
    ln -s /home/user/dataset /home/user/dataset/folderB/loop
    ln -s /home/user/dataset/folderA /home/user/dataset/folderA/loop_self

    # Set permissions
    chmod -R 777 /home/user
