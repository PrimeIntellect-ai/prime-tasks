#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    # Create directories in /opt to avoid chmod -R 777 overwriting permissions
    mkdir -p /opt/app/bin
    mkdir -p /opt/app/config
    mkdir -p /opt/app/data

    # Create files
    touch /opt/app/bin/server
    touch /opt/app/bin/suid_helper
    touch /opt/app/config/settings.yml
    touch /opt/app/data/cache.tmp

    # Set specific permissions
    chmod 755 /opt/app/bin/server
    chmod 4755 /opt/app/bin/suid_helper
    chmod 644 /opt/app/config/settings.yml
    chmod 777 /opt/app/data/cache.tmp

    # Create the user
    useradd -m -s /bin/bash user || true

    # Symlink /opt/app to /home/user/app
    # chmod -R won't follow this symlink, preserving our specific permissions
    ln -s /opt/app /home/user/app

    chmod -R 777 /home/user
