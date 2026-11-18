#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/artifact_info.env
MAJOR=3
MINOR=4
PATCH=2
BUILD_NUMBER=105
EOF

cat << 'EOF' > /home/user/expressions.txt
MAJOR + 2
MINOR * PATCH
(MAJOR + MINOR) * 2
BUILD_NUMBER - (MAJOR * 10)
EOF

chmod -R 777 /home/user
