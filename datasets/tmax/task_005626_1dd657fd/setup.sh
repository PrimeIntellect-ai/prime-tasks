#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/logs
mkdir -p /home/user/archived_chunks
mkdir -p /home/user/restored_logs

# Generate deterministic random data for log files
dd if=/dev/urandom of=/home/user/logs/app_20220315.log bs=1M count=3 status=none
dd if=/dev/urandom of=/home/user/logs/app_20220620.log bs=1M count=3 status=none
dd if=/dev/urandom of=/home/user/logs/app_20221105.log bs=1M count=3 status=none
dd if=/dev/urandom of=/home/user/logs/app_20230110.log bs=1M count=1 status=none
dd if=/dev/urandom of=/home/user/logs/app_20230505.log bs=1M count=1 status=none

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/logs /home/user/archived_chunks /home/user/restored_logs
chmod -R 777 /home/user
