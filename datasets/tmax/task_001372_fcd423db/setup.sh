#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/staging /home/user/live /home/user/backup
    touch /home/user/deploy.log

    # Create staging files
    cat << 'EOF' > /home/user/staging/app1.conf
DEPLOY=true
SETTING1=foo
SETTING2=bar
EOF

    cat << 'EOF' > /home/user/staging/app2.conf
DEPLOY=false
SETTING1=ignore
EOF

    cat << 'EOF' > /home/user/staging/app3.conf
DEPLOY=true
SETTING1=baz
EOF

    # Create existing live files
    cat << 'EOF' > /home/user/live/app1.conf
DEPLOY=true
SETTING1=old_foo
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/staging /home/user/live /home/user/backup /home/user/deploy.log
    chmod -R 777 /home/user
