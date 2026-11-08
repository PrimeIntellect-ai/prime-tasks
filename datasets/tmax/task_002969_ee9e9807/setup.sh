#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils coreutils tar gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/recovered_data/subdir1
    mkdir -p /home/user/recovered_data/subdir2

    cp /bin/ls /home/user/recovered_data/subdir1/ls_tool
    cp /bin/grep /home/user/recovered_data/subdir2/grep_tool
    cp /bin/cat /home/user/recovered_data/cat_tool

    echo "Not an ELF" > /home/user/recovered_data/fake_elf.bin
    head -c 50 /bin/ls > /home/user/recovered_data/subdir1/corrupt.elf

    chmod -R 777 /home/user
