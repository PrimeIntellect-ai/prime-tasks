#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project/src
    mkdir -p /home/user/archive

    echo "print('hello world')" > /home/user/project/src/app.py
    echo "def add(a, b): return a + b" > /home/user/project/src/utils.py
    echo "version: 1.0.0" > /home/user/project/src/config.yaml

    cat << 'EOF' > /home/user/project/deploy.log
[DEPLOY] 2023-10-01
Source: src/app.py
Target: core_app
Alias: main_app

[DEPLOY] 2023-10-02
Source: src/utils.py
Target: helpers

[DEPLOY] 2023-10-03
Source: src/config.yaml
Target: configuration
Alias: settings
EOF

    chmod -R 777 /home/user
