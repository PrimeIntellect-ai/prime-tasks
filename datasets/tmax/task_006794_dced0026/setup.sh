#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest
apt-get install -y openssh-server openssh-client gcc curl logrotate procps

useradd -m -s /bin/bash user || true

# Prepare sshd
mkdir -p /run/sshd

# Setup ssh keys for user
mkdir -p /home/user/.ssh
ssh-keygen -t rsa -N "" -f /home/user/.ssh/id_rsa
cat /home/user/.ssh/id_rsa.pub >> /home/user/.ssh/authorized_keys

# Create the fstab mock file
echo "UUID=8a9b2c3d /home/user/app_logs ext4 rw,relatime 0 2 # sre_logs" > /home/user/fstab_mock

chmod -R 777 /home/user

# Fix SSH permissions after the 777 chmod
chmod 700 /home/user/.ssh
chmod 600 /home/user/.ssh/authorized_keys
chmod 600 /home/user/.ssh/id_rsa
chown -R user:user /home/user/.ssh
