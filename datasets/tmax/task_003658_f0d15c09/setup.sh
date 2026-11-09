#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip zip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backups/raw
    mkdir -p /home/user/backups/clean

    cd /home/user/backups/raw

    # 1. Plain text file with fake extension
    echo "Important log data" > plain.dat

    # 2. GZIP containing a text file
    echo "Database dump row 1" > db_dump.txt
    gzip db_dump.txt
    mv db_dump.txt.gz compressed_db.tmp

    # 3. ZIP containing a GZIP containing a text file (Nested)
    echo "Super secret configuration" > secret.conf
    gzip secret.conf
    zip nested.zip secret.conf.gz
    rm secret.conf.gz
    mv nested.zip mystery.bak

    # 4. Infinite symlink loop
    ln -s loop_b.link loop_a.link
    ln -s loop_a.link loop_b.link

    chown -R user:user /home/user
    chmod -R 777 /home/user
