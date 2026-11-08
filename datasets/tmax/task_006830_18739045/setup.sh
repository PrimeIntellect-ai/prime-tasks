#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo iptables
pip3 install pytest

useradd -m -s /bin/bash user || true

echo -n "700a0614eb58c2794c4ddfe00c0ba13c9bd6ebbe50af98e8f81dfce1104e76d9" > /home/user/legacy_hash.txt

chmod -R 777 /home/user
