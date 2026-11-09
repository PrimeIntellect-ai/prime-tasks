#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

useradd -m -s /bin/bash user || true

dd if=/dev/urandom of=/home/user/archive.dat bs=1 count=10000 status=none

chmod -R 777 /home/user
