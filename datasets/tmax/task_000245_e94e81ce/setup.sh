#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/live_config
mkdir -p /home/user/baseline_temp

# Create baseline files
echo "setting=1" > /home/user/baseline_temp/app.conf
echo "host=localhost" > /home/user/baseline_temp/db.conf
echo "enabled=true" > /home/user/baseline_temp/cache.conf

# Create the baseline archive
cd /home/user/baseline_temp && tar -czf /home/user/base_config.tar.gz *.conf
rm -rf /home/user/baseline_temp

# Create live files
echo "setting=1" > /home/user/live_config/app.conf
echo "host=192.168.1.100" > /home/user/live_config/db.conf
echo "enabled=true" > /home/user/live_config/cache.conf
echo "mode=fast" > /home/user/live_config/new.conf

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
