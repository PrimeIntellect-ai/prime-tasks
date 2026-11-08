#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip squashfuse squashfs-tools acl openssl curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /tmp/dummy_logs
    echo "Jan 14 10:00:01 server sshd[1234]: Accepted password for root from 10.0.0.5 port 50123 ssh2" > /tmp/dummy_logs/auth1.log
    echo "Jan 14 10:05:22 server sshd[1235]: Failed publickey for admin from 192.168.1.10 port 44322 ssh2" >> /tmp/dummy_logs/auth1.log
    echo "Jan 14 10:07:11 server sshd[1236]: Silent rejection: Failed publickey for unknown from 10.1.1.1 port 11223 ssh2" > /tmp/dummy_logs/auth2.log
    echo "Jan 14 10:10:00 server sshd[1237]: Connection closed by 10.0.0.5" >> /tmp/dummy_logs/auth2.log

    mksquashfs /tmp/dummy_logs /home/user/logs.sqsh -noappend
    rm -rf /tmp/dummy_logs

    chown user:user /home/user/logs.sqsh
    chmod -R 777 /home/user
