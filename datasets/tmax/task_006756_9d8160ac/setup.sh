#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create the initial database with the specific values
    sqlite3 sensor.db "CREATE TABLE measurements (value REAL);"
    sqlite3 sensor.db "INSERT INTO measurements VALUES (1000000001.1), (1000000001.3), (1000000001.5);"

    # Corrupt the SQLite database header (first 16 bytes contain the SQLite signature)
    dd if=/dev/zero of=sensor.db bs=1 count=16 conv=notrunc

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
