#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data/logs/app1
    mkdir -p /home/user/data/logs/app2/nested

    # Inactive logs
    echo "error at line 1\nerror at line 2" > /home/user/data/logs/app1/db.log
    echo "login success user admin\nlogin failed user test" > /home/user/data/logs/app2/auth.log
    echo "compilation finished" > /home/user/data/logs/app2/nested/build.log

    # Active logs
    echo "writing active data..." > /home/user/data/logs/app1/server.log
    touch /home/user/data/logs/app1/server.log.lock

    echo "metric stream" > /home/user/data/logs/app2/nested/metrics.log
    touch /home/user/data/logs/app2/nested/metrics.log.lock

    chown -R user:user /home/user/data
    chmod -R 777 /home/user
