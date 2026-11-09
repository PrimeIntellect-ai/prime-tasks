#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/legacy_project/setup
    mkdir -p /home/user/legacy_project/math
    mkdir -p /home/user/legacy_project/utils

    cat << 'EOF' > /home/user/legacy_project/main.lasm
RUN init.lasm
RUN compute.lasm
INC X 10
OUT X
EOF

    cat << 'EOF' > /home/user/legacy_project/setup/init.lasm
INC X 5
INC Y 2
EOF

    cat << 'EOF' > /home/user/legacy_project/math/compute.lasm
RUN init.lasm
RUN helper.lasm
DEC X Y
INC Z 20
OUT Z
EOF

    cat << 'EOF' > /home/user/legacy_project/utils/helper.lasm
INC Y 3
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
