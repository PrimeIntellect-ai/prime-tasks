#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/source_data/app
    mkdir -p /home/user/source_data/db

    echo "System started at 00:00" > /home/user/source_data/app/sys.log
    echo "Error: DB connection timeout" > /home/user/source_data/app/error.log
    echo '{"config": "default"}' > /home/user/source_data/app/config.json
    echo "SELECT * FROM users;" > /home/user/source_data/db/query.log
    echo "Read me first!" > /home/user/source_data/readme.txt

    chmod -R 777 /home/user
