#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/app_tree/dirA/dirB
    mkdir -p /home/user/app_tree/dirC

    # Create real ELF files by copying system binaries
    cp /bin/ls /home/user/app_tree/dirA/utility_ls
    cp /bin/cat /home/user/app_tree/dirC/utility_cat

    # Create fake files (non-ELF)
    echo "This is not an ELF file" > /home/user/app_tree/dirA/readme.txt
    dd if=/dev/urandom of=/home/user/app_tree/dirC/random.bin bs=1K count=1 2>/dev/null

    # Create a symlink loop
    ln -s /home/user/app_tree/dirA /home/user/app_tree/dirA/dirB/loop_link

    # Create a symlink to an ELF file (should be resolved and copied)
    ln -s /home/user/app_tree/dirA/utility_ls /home/user/app_tree/dirC/link_ls

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/app_tree
    chmod -R 777 /home/user
