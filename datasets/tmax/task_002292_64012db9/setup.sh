#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tzdata
    pip3 install pytest pytz

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/services-available
    echo '{"name": "web", "port": 8080}' > /home/user/services-available/web.json
    echo '{"name": "api", "port": 8081}' > /home/user/services-available/api.json
    echo '{"name": "db", "port": 8082}' > /home/user/services-available/db.json

    chmod -R 777 /home/user
