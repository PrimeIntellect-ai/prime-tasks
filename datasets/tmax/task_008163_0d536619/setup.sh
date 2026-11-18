#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install --default-timeout=100 pytest
apt-get install -y cargo haproxy netcat-openbsd tar bash

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
