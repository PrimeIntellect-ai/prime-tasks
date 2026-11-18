#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user/project
    cat << 'EOF' > /home/user/project/build.deps
Core -> Utils, Math
Math -> Utils
Network -> Core, Crypto
Crypto -> Utils
App -> Network, UI
UI -> Core
Utils -> Network
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
