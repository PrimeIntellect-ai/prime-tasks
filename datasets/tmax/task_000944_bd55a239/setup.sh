#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip build-essential
pip3 install pytest hypothesis

useradd -m -s /bin/bash user || true
mkdir -p /home/user/project

chmod -R 777 /home/user
