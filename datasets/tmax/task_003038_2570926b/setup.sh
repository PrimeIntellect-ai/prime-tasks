#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk diffutils
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/ref_data.txt
5.1
4.2
6.3
3.8
5.5
4.9
2.1
5.8
4.5
6.0
EOF

chmod -R 777 /home/user
