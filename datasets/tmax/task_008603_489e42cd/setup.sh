#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/db_backups/cluster1/node_a
    mkdir -p /home/user/db_backups/cluster1/node_b
    mkdir -p /home/user/db_backups/cluster2/data
    mkdir -p /home/user/external_dir

    python3 -c '
with open("/home/user/db_backups/cluster1/node_a/wal_001.log", "wb") as f: f.write(b"WAL\x01\x00\x11\x22")
with open("/home/user/db_backups/cluster2/data/wal_003.log", "wb") as f: f.write(b"WAL\x01\x99\x88\x77")
with open("/home/user/external_dir/wal_004.log", "wb") as f: f.write(b"WAL\x01\xAA\xBB\xCC")
with open("/home/user/db_backups/cluster1/node_b/wal_002.log", "wb") as f: f.write(b"WAL\x02\x00\x11\x22")
with open("/home/user/db_backups/cluster2/data/readme.txt", "wb") as f: f.write(b"TXT\x01\x00\x11\x22")
'

    ln -s /home/user/db_backups/cluster2 /home/user/db_backups/cluster2/data/link_back
    ln -s /home/user/external_dir /home/user/db_backups/external

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/db_backups
    chown -R user:user /home/user/external_dir
    chmod -R 777 /home/user
