#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/project_data
dd if=/dev/zero of=/home/user/project_data/data_dump.bin bs=1048576 count=400 2>/dev/null
touch /home/user/.bash_profile

chmod -R 777 /home/user
