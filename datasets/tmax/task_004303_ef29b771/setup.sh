#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/legacy_source/dir1
    mkdir -p /home/user/legacy_source/dir2/subdir

    # Create JSON files
    cat <<EOF > /home/user/legacy_source/dir1/config1.json
{
  "name": "ServiceA",
  "port": 8080
}
EOF

    cat <<EOF > /home/user/legacy_source/dir2/subdir/settings.json
{
  "name": "ServiceB",
  "enabled": false
}
EOF

    cat <<EOF > /home/user/legacy_source/root_level.json
{
  "app": "LegacyApp",
  "version": "1.0.0"
}
EOF

    # Create archive
    cd /home/user/legacy_source
    tar -czf /home/user/legacy_assets.tar.gz .
    cd /home/user
    rm -rf /home/user/legacy_source

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
