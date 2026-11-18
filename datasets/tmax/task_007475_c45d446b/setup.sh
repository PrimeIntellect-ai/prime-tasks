#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/active_logs
    echo -n "Application started. Errors: 0" > /home/user/active_logs/app.log
    echo -n "Temporary data processing..." > /home/user/active_logs/temp.tmp
    echo -n "System OK" > /home/user/active_logs/sys.log
    echo -n "User admin logged into the system" > /home/user/active_logs/auth.log

    chown -R user:user /home/user/active_logs
    chmod -R 777 /home/user
