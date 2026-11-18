#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl logrotate netcat-openbsd cargo rustc
    pip3 install pytest

    mkdir -p /home/user/logs
    mkdir -p /home/user/smtp_monitor
    echo "sysadmins: root, admin" > /home/user/mail_aliases.txt
    echo "net-admins: bob, charlie" >> /home/user/mail_aliases.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
