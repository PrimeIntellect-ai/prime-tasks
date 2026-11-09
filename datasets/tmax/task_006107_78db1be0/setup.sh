#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git cron
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data_dir
head -c 2000 /dev/zero > /home/user/data_dir/initial_data.bin

mkdir -p /home/user/dash_repo
cd /home/user/dash_repo
git init
git config user.name "Test User"
git config user.email "test@example.com"

chmod -R 777 /home/user
