#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/output
dd if=/dev/urandom of=/home/user/project_data.bin bs=1 count=10240

cat << 'EOF' > /home/user/split_config.txt
level1.bin 2048
level2.bin 4096
sprites.bin 1024
audio.bin 2048
EOF

chmod -R 777 /home/user
