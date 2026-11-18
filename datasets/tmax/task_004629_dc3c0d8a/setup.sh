#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/releases/v1 /home/user/releases/v2
    touch /home/user/releases/v1/config.ini
    touch /home/user/releases/v2/config.ini

    mkdir -p /home/user/mock_homes/alice/logs
    mkdir -p /home/user/mock_homes/bob/logs
    mkdir -p /home/user/mock_homes/charlie/logs

    ln -s /home/user/releases/v1/config.ini /home/user/mock_homes/alice/app_config
    ln -s /home/user/releases/v1/config.ini /home/user/mock_homes/bob/app_config
    ln -s /home/user/releases/v1/config.ini /home/user/mock_homes/charlie/app_config

    cat << 'EOF' > /home/user/mock_passwd
alice:x:1000:1001:Alice:/home/user/mock_homes/alice:/bin/bash
bob:x:1001:1001:Bob:/home/user/mock_homes/bob:/bin/bash
charlie:x:1002:1002:Charlie:/home/user/mock_homes/charlie:/bin/bash
EOF

    rm -f /home/user/logrotate_updates.conf

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
