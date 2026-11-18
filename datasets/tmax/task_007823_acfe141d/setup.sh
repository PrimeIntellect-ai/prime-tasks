#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/logs_archive/web
    mkdir -p /home/user/logs_archive/db
    mkdir -p /home/user/compressed_logs

    python3 -c "with open('/home/user/logs_archive/web/access.dat', 'wb') as f: f.write(b'C' * 15000)"
    python3 -c "with open('/home/user/logs_archive/db/small.log', 'wb') as f: f.write(b'D' * 10240)"
    python3 -c "with open('/home/user/logs_archive/web/large1.log', 'wb') as f: f.write(b'A' * 5120 + b'B' * 5120 + b'C' * 1760)"
    python3 -c "with open('/home/user/logs_archive/db/large2.log', 'wb') as f: f.write(b'X' * 5000 + b'Y' * 5000 + b'Z' * 5000)"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
