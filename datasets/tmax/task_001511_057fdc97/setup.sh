#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cron logrotate
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/src
    mkdir -p /home/user/app/config
    mkdir -p /home/user/app/scripts
    mkdir -p /home/user/data
    mkdir -p /home/user/backups

    echo "dummy data" > /home/user/data/file1.txt
    echo "more data" > /home/user/data/file2.txt

    cat << 'EOF' > /home/user/app/src/monitor.c
#include <stdio.h>
#include <stdlib.h>
#include <sys/statvfs.h>

int main() {
    FILE *log = fopen("/home/user/app/logs/monitor.log", "a");
    // BUG: Missing NULL check for log pointer, directory doesn't exist.

    struct statvfs buf;
    if (statvfs("/home/user/data", &buf) == 0) {
        unsigned long free_space = buf.f_bfree * buf.f_frsize;
        fprintf(log, "Free space: %lu bytes\n", free_space);
    }

    fclose(log); // Will segfault here or at fprintf if log is NULL
    return 0;
}
EOF

    chmod -R 777 /home/user
