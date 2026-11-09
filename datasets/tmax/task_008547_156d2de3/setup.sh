#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/schema_v2.txt
API_LEVEL=33
MIN_API=24
RAM_MB=4096
IS_PRO_BUILD=1
CPU_CORES=8
EOF

cat << 'EOF' > /home/user/constraints.txt
FEATURE_PRO_UI = IS_PRO_BUILD * FEATURE_ADVANCED
FEATURE_CAMERA_X = API_LEVEL > 30
FEATURE_ADVANCED = FEATURE_CAMERA_X + FEATURE_HEAVY_PROCESSING
FEATURE_HEAVY_PROCESSING = RAM_MB > 2048
HAS_MULTI_CORE = CPU_CORES > 1
LEGACY_SUPPORT = MIN_API < 21
FINAL_SCORE = FEATURE_PRO_UI + HAS_MULTI_CORE
EOF

chmod -R 777 /home/user
