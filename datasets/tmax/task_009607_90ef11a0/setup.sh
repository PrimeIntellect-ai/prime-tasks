#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/src /home/user/app /home/user/backup

    cat << 'EOF' > /home/user/src/monitor.c
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <pid>\n", argv[0]);
        return 1;
    }

    int pid = atoi(argv[1]);
    FILE *log = fopen("health.log", "a");
    if (!log) {
        perror("Failed to open log");
        return 1;
    }

    if (kill(pid, 0) == 0) {
        fprintf(log, "STATUS: OK\n");
    } else {
        fprintf(log, "STATUS: DOWN\n");
    }
    fclose(log);

    // Backup the log
    int ret = system("tar -czf health_backup.tar.gz health.log");
    if (ret != 0) {
        return 1;
    }

    return 0;
}
EOF

    chmod -R 777 /home/user
