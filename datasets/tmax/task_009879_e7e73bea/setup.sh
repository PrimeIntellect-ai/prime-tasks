#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/pool
mkdir -p /home/user/ports
mkdir -p /home/user/bin

echo "8081" > /home/user/ports/8081.txt
echo "8082" > /home/user/ports/8082.txt
echo "8083" > /home/user/ports/8083.txt
echo "8084" > /home/user/ports/8084.txt

ln -s /home/user/ports/8081.txt /home/user/pool/srv1
ln -s /home/user/ports/8082.txt /home/user/pool/srv2
ln -s /home/user/ports/8083.txt /home/user/pool/srv3
ln -s /home/user/ports/8084.txt /home/user/pool/srv4

chmod -R 777 /home/user
