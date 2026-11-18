#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/active_logs
    mkdir -p /home/user/archived_logs

    echo "Web log line 1: GET /index.html 200" > /home/user/active_logs/web.log
    echo "Web log line 2: POST /login 401" >> /home/user/active_logs/web.log
    echo "Database connection established" > /home/user/active_logs/db.log
    for i in $(seq 1 100); do echo "DB query $i executed" >> /home/user/active_logs/db.log; done
    echo "Auth failure: user admin from 192.168.1.50" > /home/user/active_logs/auth.log
    echo "Auth success: user root from 10.0.0.5" >> /home/user/active_logs/auth.log

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/active_logs
    chown -R user:user /home/user/archived_logs
    chmod -R 777 /home/user
