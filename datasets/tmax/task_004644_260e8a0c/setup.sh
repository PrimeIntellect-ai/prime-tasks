#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils tar gzip
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/packer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    char *in = NULL;
    char *out = NULL;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-i") == 0 && i + 1 < argc) in = argv[++i];
        if (strcmp(argv[i], "-o") == 0 && i + 1 < argc) out = argv[++i];
    }
    if (in && out) {
        char cmd[1024];
        snprintf(cmd, sizeof(cmd), "tar -czf %s -C %s .", out, in);
        system(cmd);
    }
    return 0;
}
EOF
    gcc -O2 -o /app/legacy_packer /app/packer.c
    strip /app/legacy_packer
    rm /app/packer.c

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/backup_config.json
{
  "target_directories": ["/home/user/logs/app1", "/home/user/logs/app2"],
  "last_run_timestamp": 1710000000
}
EOF

    mkdir -p /home/user/logs/app1
    mkdir -p /home/user/logs/app2

    cat << 'EOF' > /home/user/logs/app1/server.log
[2024-03-09 10:00:00] [INFO] Server started normally.
[2024-03-09 10:05:00] [ERROR] Database connection failed.
Traceback (most recent call last):
  File "db.py", line 42, in connect
ConnectionRefusedError: port 5432
[2024-03-09 10:06:00] [DEBUG] Retrying connection...
EOF
    touch -m -d @1710005000 /home/user/logs/app1/server.log

    cat << 'EOF' > /home/user/logs/app2/worker.log
[2023-11-01 08:00:00] [CRITICAL] Out of memory!
Heap dump saved.
EOF
    touch -m -d @1700000000 /home/user/logs/app2/worker.log

    cat << 'EOF' > /home/user/logs/app2/auth.log
[2024-03-09 11:00:00] [WARNING] Invalid login attempt.
[2024-03-09 11:05:00] [CRITICAL] Segment fault in auth module.
Core dumped.
Registers dumped.
[2024-03-09 11:06:00] [INFO] Rebooting auth module.
EOF
    touch -m -d @1710010000 /home/user/logs/app2/auth.log

    chmod -R 777 /home/user
