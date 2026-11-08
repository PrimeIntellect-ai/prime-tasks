#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sudo
pip3 install pytest

# Install dependencies the agent might need or try to install
apt-get install -y libsqlite3-dev nlohmann-json3-dev build-essential cmake

# Create user and configure passwordless sudo
useradd -m -s /bin/bash user || true
echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Ensure proper permissions
chmod -R 777 /home/user
