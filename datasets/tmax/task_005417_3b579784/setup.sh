#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go openssh-client
    pip3 install pytest

    mkdir -p /home/user/app_users/alice
    mkdir -p /home/user/app_users/bob
    mkdir -p /home/user/app_users/admin

    COMPROMISED_KEY_1="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCcompromised1 dummy@host"
    COMPROMISED_KEY_2="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIcompromised2 dummy@host"
    SAFE_KEY_1="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCsafe1 alice@host"
    SAFE_KEY_2="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIsafe2 bob@host"

    echo "$COMPROMISED_KEY_1" > /home/user/compromised.list
    echo "$COMPROMISED_KEY_2" >> /home/user/compromised.list

    echo "$SAFE_KEY_1" > /home/user/app_users/alice/authorized_keys
    echo "$COMPROMISED_KEY_1" >> /home/user/app_users/alice/authorized_keys
    echo "$COMPROMISED_KEY_2" >> /home/user/app_users/alice/authorized_keys

    echo "$SAFE_KEY_2" > /home/user/app_users/bob/authorized_keys
    echo "$COMPROMISED_KEY_2" >> /home/user/app_users/bob/authorized_keys

    echo "$COMPROMISED_KEY_1" > /home/user/app_users/admin/authorized_keys

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/app_users /home/user/compromised.list
    chmod -R 777 /home/user
