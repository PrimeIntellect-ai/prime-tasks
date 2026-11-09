#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pyyaml

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_configs/sub1
    mkdir -p /home/user/app_configs/sub2

    cat << 'EOF' > /home/user/last_backup.json
{
  "last_backup_time": 1650000000
}
EOF

    echo '{"app": "old1"}' > /home/user/app_configs/old_config.json
    touch -d @1600000000 /home/user/app_configs/old_config.json

    echo '{"app": "old2"}' > /home/user/app_configs/sub1/legacy.json
    touch -d @1640000000 /home/user/app_configs/sub1/legacy.json

    echo '<xml>old</xml>' > /home/user/app_configs/data.xml
    touch -d @1700000000 /home/user/app_configs/data.xml

    echo '{"app": "new_1"}' > /home/user/app_configs/sub2/active_config.json
    touch -d @1700000000 /home/user/app_configs/sub2/active_config.json

    echo '{"app": "updated"}' > /home/user/app_configs/settings.json
    touch -d @1660000000 /home/user/app_configs/settings.json

    chown -R user:user /home/user/app_configs
    chown user:user /home/user/last_backup.json

    chmod -R 777 /home/user
