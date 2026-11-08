#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/current_deps.txt
alpha@1.0.0
beta@2.1.0
delta@1.4.0
gamma@3.0.0
EOF

    cat << 'EOF' > /home/user/legacy_script.ops
INSTALL alpha@1.0.0
INSTALL beta@2.1.0
INSTALL gamma@3.0.0
REMOVE beta
INSTALL delta@1.5.0
REPLACE alpha omega@2.0.0
INSTALL epsilon@1.1.1
REMOVE gamma
INSTALL zeta@4.0.0
INSTALL zeta@4.1.0
REPLACE zeta theta@1.0.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
