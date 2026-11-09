#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl build-essential rustc cargo
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/build_config.bcd
ScreenWidth = 1080
ScreenHeight = 1920
Multiplier = 4
Buffer = 512
MaxMemory = ScreenWidth ScreenHeight * Multiplier * Buffer +
ApiEndpoint = /api/v2/config
RateLimit = 45
BurstThreshold = RateLimit 2 * 10 +
EOF

chmod -R 777 /home/user
