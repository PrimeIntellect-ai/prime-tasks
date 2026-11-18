#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/data_to_backup/dir1
    mkdir -p /home/user/data_to_backup/dir2

    # Create files
    echo "file A" > /home/user/data_to_backup/a.txt
    dd if=/dev/urandom of=/home/user/data_to_backup/b.bin bs=1K count=1 2>/dev/null
    echo "file C" > /home/user/data_to_backup/dir1/c.txt
    echo "file D" > /home/user/data_to_backup/dir2/d.txt

    # Create symlinks
    ln -s /home/user/data_to_backup/a.txt /home/user/data_to_backup/dir1/link_to_a
    ln -s /home/user/data_to_backup /home/user/data_to_backup/dir1/loop_to_base
    ln -s /home/user/data_to_backup/dir1 /home/user/data_to_backup/dir2/link_to_dir1

    chmod -R 777 /home/user
