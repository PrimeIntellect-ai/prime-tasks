#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create directories and files
    mkdir -p /home/user/forensics
    dd if=/dev/urandom of=/home/user/forensics/suspicious.dmp bs=1K count=512 2>/dev/null
    echo -n "SOME_OTHER_VAR=12345" >> /home/user/forensics/suspicious.dmp
    echo -n "C2_SERVER_IP=203.0.113.85" >> /home/user/forensics/suspicious.dmp
    echo -n "CONNECTION_STATUS=ACTIVE" >> /home/user/forensics/suspicious.dmp
    dd if=/dev/urandom bs=1K count=512 >> /home/user/forensics/suspicious.dmp 2>/dev/null
    chmod 644 /home/user/forensics/suspicious.dmp

    # Set permissions
    chmod -R 777 /home/user
