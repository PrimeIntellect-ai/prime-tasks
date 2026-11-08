#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/evidence/proc_9999/
printf "python3\0/tmp/kworker.py\0--c2-payload\0MTk4LjUxLjEwMC40NTo0NDQ0\0--verify\0716e9104b0b134f5147be15e913a290d235c3459c3cb06cdb5ccb00b46ebf700\0" > /home/user/evidence/proc_9999/cmdline

chmod -R 777 /home/user
