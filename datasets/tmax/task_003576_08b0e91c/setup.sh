#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/old_crash.log
2023-10-24T11:59:00Z [INFO] Starting daemon...
2023-10-24T11:59:01Z [CRITICAL FATAL ERROR] Null pointer dereference
2023-10-24T12:05:00Z [INFO] Starting daemon...
2023-10-24T12:05:01Z [CRITICAL FATAL ERROR] Segfault
EOF

    cat << 'EOF' > /home/user/daemon.conf
LOG_LEVEL=DEBUG
PID_PATH=/home/user/daemon.pid
EOF

    mkdir -p /home/user/daemon_repo
    cat << 'EOF' > /home/user/daemon_repo/daemon.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

int main() {
    FILE *f = fopen("/home/user/daemon.conf", "r");
    if (!f) return 1;
    char *line = NULL;
    size_t len = 0;
    getline(&line, &len, f);
    getline(&line, &len, f);
    fclose(f);

    char *log_path;
    strcpy(log_path, "/home/user/daemon.log");

    FILE *log = fopen(log_path, "w");
    if (log) {
        fprintf(log, "Daemon started successfully\n");
        fclose(log);
    }

    FILE *pidf = fopen("/home/user/daemon.pid", "w");
    if (pidf) {
        fprintf(pidf, "%d\n", getpid());
        fclose(pidf);
    }

    while(1) {
        sleep(10);
    }
    return 0;
}
EOF

    cd /home/user/daemon_repo
    git init
    git config --local user.email "test@example.com"
    git config --local user.name "Test User"
    git add daemon.c
    git commit -m "Initial commit with broken daemon"

    chmod -R 777 /home/user
