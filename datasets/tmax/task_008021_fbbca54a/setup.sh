#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git openssh-server openssh-client iproute2
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /run/sshd

mkdir -p /home/user/.ssh
ssh-keygen -t ed25519 -f /home/user/.ssh/id_ed25519 -N ""
cat /home/user/.ssh/id_ed25519.pub >> /home/user/.ssh/authorized_keys
chmod 700 /home/user/.ssh
chmod 600 /home/user/.ssh/authorized_keys
touch /home/user/.ssh/known_hosts
echo "StrictHostKeyChecking no" >> /home/user/.ssh/config
chmod 600 /home/user/.ssh/config
chmod 644 /home/user/.ssh/known_hosts

chown -R user:user /home/user/.ssh

su - user -c "git config --global user.name 'Test User'"
su - user -c "git config --global user.email 'test@example.com'"
su - user -c "git config --global init.defaultBranch master"

chmod -R 777 /home/user
