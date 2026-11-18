#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils tar
    pip3 install pytest

    # Create the incoming directory and files
    mkdir -p /home/user/incoming
    cp /bin/ls /home/user/incoming/app1
    cp /bin/bash /home/user/incoming/app2
    echo "Some release notes" > /home/user/incoming/readme.txt

    # Create symlink loop and valid link
    cd /home/user/incoming
    ln -s loopB loopA
    ln -s loopA loopB
    ln -s app1 valid_link

    # Create the archive and clean up
    cd /home/user
    tar -czf incoming_backup.tar.gz -C /home/user/incoming .
    rm -rf /home/user/incoming

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
