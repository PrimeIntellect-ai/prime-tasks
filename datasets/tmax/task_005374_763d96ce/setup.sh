#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak curl netcat-openbsd
pip3 install pytest

mkdir -p /app
espeak -w /app/admin_memo.wav "The new base password is red dragon fly"

useradd -m -s /bin/bash user || true

echo -n "c2c19266e746dc02377b212f37c3ed0375971485669b0eaeb25f25aebbc36412" > /home/user/legacy.hash

chmod -R 777 /home/user
chmod -R 777 /app
