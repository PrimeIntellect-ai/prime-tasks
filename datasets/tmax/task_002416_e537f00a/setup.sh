#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gawk
    pip3 install pytest

    mkdir -p /home/user/artifacts
    cp /bin/ls /home/user/artifacts/bin_ls
    cp /bin/cat /home/user/artifacts/bin_cat
    echo "Not an elf" > /home/user/artifacts/readme.txt

    ln -s /home/user/artifacts/bin_ls /home/user/artifacts/link_to_ls
    ln -s /home/user/artifacts/link_to_ls /home/user/artifacts/link_to_link_to_ls

    ln -s /home/user/artifacts/loop_b /home/user/artifacts/loop_a
    ln -s /home/user/artifacts/loop_a /home/user/artifacts/loop_b

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/artifacts
    chmod -R 777 /home/user
