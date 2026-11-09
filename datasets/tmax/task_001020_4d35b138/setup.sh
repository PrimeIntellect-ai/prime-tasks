#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip unzip bzip2 tar gzip jq
    pip3 install pytest

    mkdir -p /home/user/setup/app/plugins
    mkdir -p /home/user/setup/plugin_b_dir

    cat << 'EOF' > /home/user/setup/app/core.py
# FIXME: memory leak
# TODO: add tests
def run(): pass
EOF

    cat << 'EOF' > /home/user/setup/app/plugins/plugin_a.py
# FIXME: bug 1
# FIXME: bug 2
def a(): pass
EOF

    cat << 'EOF' > /home/user/setup/plugin_b_dir/plugin_b.py
# TODO: x
# TODO: y
# TODO: z
# FIXME: w
def b(): pass
EOF

    cd /home/user/setup/plugin_b_dir
    tar -czf /home/user/setup/app/plugins/plugin_b.tar.gz plugin_b.py

    cd /home/user/setup/app/plugins
    zip -r ../plugins.zip plugin_a.py plugin_b.tar.gz
    rm plugin_a.py plugin_b.tar.gz

    cd /home/user/setup
    tar -czf /home/user/project_backup.tar.gz app

    rm -rf /home/user/setup

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
