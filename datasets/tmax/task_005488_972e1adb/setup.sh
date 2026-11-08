#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/app_data/versions/
    mkdir -p /home/user/app_data/active/
    mkdir -p /home/user/backup/

    # Create target version files
    echo "port=5432" > /home/user/app_data/versions/db_config_v1.conf
    echo "port=5433" > /home/user/app_data/versions/db_config_v2.conf
    echo '{"key": "old"}' > /home/user/app_data/versions/api_keys_v1.json
    echo '{"key": "new"}' > /home/user/app_data/versions/api_keys_v3.json

    # Create manifest file
    cat << 'EOF' > /home/user/manifest.conf
db.conf=db_config_v2.conf
keys.json=api_keys_v3.json
EOF

    # Create botched active directory state
    ln -s /home/user/app_data/versions/db_config_v1.conf /home/user/app_data/active/db.conf
    ln -s /dev/null /home/user/app_data/active/old_cache.bin
    touch /home/user/app_data/active/rogue_file.txt

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
