#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar
    pip3 install pytest

    mkdir -p /home/user/setup_tmp/module1
    mkdir -p /home/user/setup_tmp/module2

    # Create module 1 files
    cat << 'EOF' > /home/user/setup_tmp/module1/app.log
DEBUG: starting application
INFO: application started successfully
WARN: high memory usage detected
DEBUG: closing connection
EOF
    echo "print('hello world')" > /home/user/setup_tmp/module1/main.py

    # Create module 2 files
    cat << 'EOF' > /home/user/setup_tmp/module2/db.log
WARN: reconnecting to database
DEBUG: pinging database
INFO: database connected
EOF
    echo "timeout: 30" > /home/user/setup_tmp/module2/config.yml

    # Zip them up
    cd /home/user/setup_tmp
    zip -r module1.zip module1
    zip -r module2.zip module2

    # Tar them up
    tar -czf /home/user/project_data.tar.gz module1.zip module2.zip

    # Cleanup setup tmp
    rm -rf /home/user/setup_tmp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
