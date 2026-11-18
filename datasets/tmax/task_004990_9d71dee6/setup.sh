#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ssh_audit
    touch /home/user/ssh_audit/id_rsa
    touch /home/user/ssh_audit/id_ed25519
    touch /home/user/ssh_audit/id_ed25519.pub
    touch /home/user/ssh_audit/id_rsa.pub
    touch /home/user/ssh_audit/config
    touch /home/user/ssh_audit/authorized_keys
    touch /home/user/ssh_audit/backup_id_rsa
    touch /home/user/ssh_audit/ignore_me.txt

    chmod -R 777 /home/user

    # Restore specific permissions required for the task
    chmod 0644 /home/user/ssh_audit/id_rsa
    chmod 0600 /home/user/ssh_audit/id_ed25519
    chmod 0644 /home/user/ssh_audit/id_ed25519.pub
    chmod 0666 /home/user/ssh_audit/id_rsa.pub
    chmod 0755 /home/user/ssh_audit/config
    chmod 0600 /home/user/ssh_audit/authorized_keys
    chmod 0777 /home/user/ssh_audit/backup_id_rsa
    chmod 0777 /home/user/ssh_audit/ignore_me.txt
