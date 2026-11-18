#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo coreutils gawk
    pip3 install pytest

    mkdir -p /home/user/proc_dump/1042
    mkdir -p /home/user/proc_dump/2055
    mkdir -p /home/user/proc_dump/3099
    mkdir -p /home/user/auditor

    echo -n "authorized_binary_alpha" > /home/user/proc_dump/1042/exe
    echo -n "malicious_binary_beta" > /home/user/proc_dump/2055/exe
    echo -n "authorized_binary_gamma" > /home/user/proc_dump/3099/exe

    hash1=$(sha256sum /home/user/proc_dump/1042/exe | awk '{print $1}')
    hash3=$(sha256sum /home/user/proc_dump/3099/exe | awk '{print $1}')

    echo "$hash1" > /home/user/hashes.txt
    echo "$hash3" >> /home/user/hashes.txt

    printf "my_app\0--port=8080\0--token=c3VwZXJfc2VjcmV0X2FkbWlu\0" > /home/user/proc_dump/1042/cmdline
    printf "evil_app\0--verbose\0--token=aGFja2VkX3Rva2VuXzk5\0" > /home/user/proc_dump/2055/cmdline
    printf "db_worker\0--token=ZGJfcGFzc3dvcmQh\0--daemon\0" > /home/user/proc_dump/3099/cmdline

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
