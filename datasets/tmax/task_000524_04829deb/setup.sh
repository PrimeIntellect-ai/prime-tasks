#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc tar coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/mail_spool
    for i in $(seq 1 12); do
        touch "/home/user/mail_spool/msg_${i}.eml"
    done

    chmod -R 777 /home/user
