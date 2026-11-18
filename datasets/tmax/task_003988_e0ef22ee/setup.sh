#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip rustc tzdata
pip3 install pytest

mkdir -p /home/user/app_data
dd if=/dev/zero of=/home/user/app_data/payload.bin bs=1 count=6000

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/app_data
chmod -R 777 /home/user
