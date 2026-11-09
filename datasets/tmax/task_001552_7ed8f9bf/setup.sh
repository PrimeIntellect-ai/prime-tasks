#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sudo openmpi-bin libopenmpi-dev
pip3 install pytest numpy scipy mpi4py

useradd -m -s /bin/bash user || true
echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

chmod -R 777 /home/user
