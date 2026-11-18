#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server
pip3 install pytest flask redis

# Create the /app directory
mkdir -p /app
chmod -R 777 /app

# Create the user
useradd -m -s /bin/bash user || true

# Ensure redis-server starts when a shell is opened
echo "redis-server --daemonize yes || true" >> /etc/bash.bashrc
echo "redis-server --daemonize yes || true" >> /home/user/.bashrc
echo "redis-server --daemonize yes || true" >> /root/.bashrc

chmod -R 777 /home/user
