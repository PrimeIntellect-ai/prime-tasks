#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backups/server_alpha/
    mkdir -p /home/user/backups/server_beta/archive/
    mkdir -p /home/user/backups/server_gamma/

    # Create dummy files for safe archives
    mkdir -p /tmp/safe1/var/log
    touch /tmp/safe1/var/log/syslog
    tar -czf /home/user/backups/server_alpha/logs.tar.gz -C /tmp/safe1 .

    mkdir -p /tmp/safe2/etc
    touch /tmp/safe2/etc/config.json
    tar -czf /home/user/backups/server_gamma/config.tar.gz -C /tmp/safe2 .

    # Create dummy files for malicious archives
    mkdir -p /tmp/malicious1
    touch /tmp/malicious1/normal_file.txt

    # Create tar with zip slip manually
    python3 -c "
import tarfile
with tarfile.open('/home/user/backups/server_alpha/system.tar.gz', 'w:gz') as tar:
    info = tarfile.TarInfo(name='normal_file.txt')
    info.size = 0
    tar.addfile(info)
    info2 = tarfile.TarInfo(name='var/log/../../../etc/shadow')
    info2.size = 0
    tar.addfile(info2)
"

    python3 -c "
import tarfile
with tarfile.open('/home/user/backups/server_beta/archive/data.tar.gz', 'w:gz') as tar:
    info = tarfile.TarInfo(name='../.ssh/authorized_keys')
    info.size = 0
    tar.addfile(info)
    info2 = tarfile.TarInfo(name='data/../../etc/passwd')
    info2.size = 0
    tar.addfile(info2)
"

    chmod -R 777 /home/user
