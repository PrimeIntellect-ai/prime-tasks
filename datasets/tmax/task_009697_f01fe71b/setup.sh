#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_legacy

    cat << 'EOF' > /tmp/worker.c
#include <stdio.h>
int main() {
    const char* db_pass = "DB_PASS=LegacyPass9988!";
    const char* db_ip = "DB_IP=10.0.45.22";
    printf("Starting worker...\n");
    return 0;
}
EOF

    gcc /tmp/worker.c -o /home/user/app_legacy/worker_bin
    rm /tmp/worker.c

    cd /home/user/app_legacy
    sha256sum worker_bin > checksums.txt

    cat << 'EOF' > /home/user/app_legacy/service.py
import time

def connect_to_db():
    password = "LegacyPass9988!"
    print("Connecting to DB with password:", password)
    return True

if __name__ == "__main__":
    connect_to_db()
EOF

    chmod -R 777 /home/user
