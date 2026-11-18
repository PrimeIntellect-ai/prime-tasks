#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 g++ curl
    pip3 install pytest flask

    mkdir -p /home/user
    sqlite3 /home/user/metrics.db "CREATE TABLE calculations (id INTEGER PRIMARY KEY, n INTEGER, result INTEGER);"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
